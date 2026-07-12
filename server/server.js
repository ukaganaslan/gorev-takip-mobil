// Pano — aile/grup görev takip uygulaması backend'i.
// Sıfır npm bağımlılığı: node:http + node:sqlite + node:crypto (Node 24+).
// Çalıştır: node server.js  (PORT ortam değişkeni ile port değiştirilebilir, varsayılan 4000)

'use strict';

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const PORT = Number(process.env.PORT || 4000);
const DATA_DIR = path.join(__dirname, 'data');
fs.mkdirSync(DATA_DIR, { recursive: true });

// ---------------------------------------------------------------- veritabanı

const db = new DatabaseSync(path.join(DATA_DIR, 'pano.db'));
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  salt          TEXT NOT NULL,
  first_name    TEXT,
  last_name     TEXT,
  email         TEXT,
  created_at    TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS groups (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  founder_id  INTEGER NOT NULL REFERENCES users(id),
  invite_code TEXT NOT NULL UNIQUE,
  created_at  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS group_members (
  group_id  INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TEXT NOT NULL,
  PRIMARY KEY (group_id, user_id)
);
CREATE TABLE IF NOT EXISTS categories (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  color      TEXT NOT NULL,
  owner_id   INTEGER NOT NULL REFERENCES users(id),
  group_id   INTEGER REFERENCES groups(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tasks (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  category_id  INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  description  TEXT,
  due_date     TEXT,
  created_by   INTEGER NOT NULL REFERENCES users(id),
  completed_by INTEGER REFERENCES users(id),
  completed_at TEXT,
  created_at   TEXT NOT NULL
);
`);

// Etkinlik akışı: görev hareketlerinin kalıcı kaydı. actor_name bilerek
// denormalize — hesap silinse bile geçmiş okunur kalır.
db.exec(`
CREATE TABLE IF NOT EXISTS activity (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id    INTEGER NOT NULL,
  actor_name  TEXT NOT NULL,
  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  action      TEXT NOT NULL,
  task_title  TEXT NOT NULL,
  created_at  TEXT NOT NULL
);
`);

// Şema migration'ları: eski veritabanlarına yeni sütunları ekler.
{
  const taskCols = db.prepare('PRAGMA table_info(tasks)').all().map((c) => c.name);
  if (!taskCols.includes('assigned_to'))
    db.exec('ALTER TABLE tasks ADD COLUMN assigned_to INTEGER REFERENCES users(id)');
  if (!taskCols.includes('recurrence'))
    db.exec('ALTER TABLE tasks ADD COLUMN recurrence TEXT');
}

// ------------------------------------------------------------------ yardımcı

const now = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

const SECRET_FILE = path.join(DATA_DIR, 'secret.key');
if (!fs.existsSync(SECRET_FILE)) {
  fs.writeFileSync(SECRET_FILE, crypto.randomBytes(64).toString('hex'), { mode: 0o600 });
}
const SECRET = fs.readFileSync(SECRET_FILE, 'utf8').trim();

const b64url = (buf) => Buffer.from(buf).toString('base64url');

function signToken(userId) {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const exp = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 90; // 90 gün
  const payload = b64url(JSON.stringify({ uid: userId, exp }));
  const sig = crypto.createHmac('sha256', SECRET).update(`${header}.${payload}`).digest('base64url');
  return `${header}.${payload}.${sig}`;
}

function verifyToken(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  const expected = crypto.createHmac('sha256', SECRET).update(`${parts[0]}.${parts[1]}`).digest('base64url');
  const a = Buffer.from(parts[2]), b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    if (!payload.uid || payload.exp < Date.now() / 1000) return null;
    return payload.uid;
  } catch { return null; }
}

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString('hex');
}

class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

const publicUser = (u) => ({
  id: u.id, username: u.username,
  firstName: u.first_name, lastName: u.last_name, email: u.email,
});

const displayName = (u) => u.first_name || u.username;

function makeInviteCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  for (;;) {
    let code = '';
    for (let i = 0; i < 8; i++) code += chars[crypto.randomInt(chars.length)];
    if (!db.prepare('SELECT 1 FROM groups WHERE invite_code = ?').get(code)) return code;
  }
}

// ------------------------------------------------- gerçek zamanlı senkron (SSE)

// userId -> Set<http.ServerResponse>
const sseClients = new Map();

function sseSubscribe(userId, res) {
  if (!sseClients.has(userId)) sseClients.set(userId, new Set());
  sseClients.get(userId).add(res);
  res.on('close', () => {
    const set = sseClients.get(userId);
    if (set) { set.delete(res); if (set.size === 0) sseClients.delete(userId); }
  });
}

// Değişiklikten etkilenen kullanıcılara "yenile" sinyali gönderir.
function notify(userIds, payload = {}) {
  const data = `event: sync\ndata: ${JSON.stringify(payload)}\n\n`;
  for (const uid of new Set(userIds)) {
    const set = sseClients.get(uid);
    if (set) for (const res of set) res.write(data);
  }
}

function groupMemberIds(groupId) {
  return db.prepare('SELECT user_id FROM group_members WHERE group_id = ?')
    .all(groupId).map((r) => r.user_id);
}

// Kategori kişiselse sahibi, grup kategorisiyse tüm grup üyeleri etkilenir.
function categoryAudience(category) {
  return category.group_id ? groupMemberIds(category.group_id) : [category.owner_id];
}

setInterval(() => {
  for (const set of sseClients.values())
    for (const res of set) res.write(': ping\n\n');
}, 25000).unref();

// ------------------------------------------------------------ erişim kontrolleri

function getCategoryForUser(categoryId, userId) {
  const cat = db.prepare('SELECT * FROM categories WHERE id = ?').get(categoryId);
  if (!cat) throw new ApiError(404, 'Kategori bulunamadı.');
  if (cat.group_id) {
    const member = db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?')
      .get(cat.group_id, userId);
    if (!member) throw new ApiError(403, 'Bu kategoriye erişimin yok.');
  } else if (cat.owner_id !== userId) {
    throw new ApiError(403, 'Bu kategoriye erişimin yok.');
  }
  return cat;
}

function getTaskForUser(taskId, userId) {
  const task = db.prepare('SELECT * FROM tasks WHERE id = ?').get(taskId);
  if (!task) throw new ApiError(404, 'Görev bulunamadı.');
  const cat = getCategoryForUser(task.category_id, userId);
  return { task, cat };
}

// ------------------------------------------------------------------ handler'lar

const taskRowSql = `
  SELECT t.*,
         cu.first_name AS creator_first, cu.username AS creator_username,
         du.first_name AS completer_first, du.username AS completer_username,
         au.first_name AS assignee_first, au.username AS assignee_username
  FROM tasks t
  JOIN users cu ON cu.id = t.created_by
  LEFT JOIN users du ON du.id = t.completed_by
  LEFT JOIN users au ON au.id = t.assigned_to
`;

const taskJson = (t) => ({
  id: t.id,
  title: t.title,
  description: t.description,
  dueDate: t.due_date,
  createdBy: t.created_by,
  createdByName: t.creator_first || t.creator_username,
  assignedTo: t.assigned_to,
  assignedToName: t.assigned_to ? (t.assignee_first || t.assignee_username) : null,
  recurrence: t.recurrence,
  completedBy: t.completed_by,
  completedByName: t.completed_by ? (t.completer_first || t.completer_username) : null,
  completedAt: t.completed_at,
  createdAt: t.created_at,
});

const RECURRENCES = ['daily', 'weekly', 'monthly'];

function validateRecurrence(recurrence, dueDate) {
  if (recurrence == null) return null;
  if (!RECURRENCES.includes(recurrence))
    throw new ApiError(400, 'Tekrar değeri daily, weekly veya monthly olabilir.');
  if (!dueDate)
    throw new ApiError(400, 'Tekrarlayan görev için son tarih gerekli.');
  return recurrence;
}

// Bir sonraki tekrar tarihi: aralık eklenir; görev geç tamamlandıysa
// geçmişte kalmasın diye bugünü geçene kadar ilerletilir.
function nextDueDate(dueStr, recurrence) {
  const d = new Date(dueStr);
  const today = new Date();
  do {
    if (recurrence === 'daily') d.setDate(d.getDate() + 1);
    else if (recurrence === 'weekly') d.setDate(d.getDate() + 7);
    else d.setMonth(d.getMonth() + 1);
  } while (d < today);
  return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function logActivity(actor, cat, action, taskTitle) {
  db.prepare('INSERT INTO activity (actor_id, actor_name, category_id, action, task_title, created_at) VALUES (?,?,?,?,?,?)')
    .run(actor.id, displayName(actor), cat.id, action, taskTitle, now());
}

// Atanan kişi kategoriye erişebilen biri olmalı.
function validateAssignee(cat, assignedTo) {
  if (assignedTo == null) return null;
  const uid = Number(assignedTo);
  if (cat.group_id) {
    if (!db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(cat.group_id, uid))
      throw new ApiError(400, 'Atanan kişi bu grubun üyesi değil.');
  } else if (uid !== cat.owner_id) {
    throw new ApiError(400, 'Kişisel kategoride görev yalnızca sana atanabilir.');
  }
  return uid;
}

function groupJson(g) {
  const members = db.prepare(`
    SELECT u.id, u.username, u.first_name FROM group_members gm
    JOIN users u ON u.id = gm.user_id WHERE gm.group_id = ? ORDER BY gm.joined_at
  `).all(g.id).map((m) => ({ id: m.id, username: m.username, firstName: m.first_name }));
  return { id: g.id, name: g.name, founderId: g.founder_id, inviteCode: g.invite_code, members };
}

const categoryJson = (c) => {
  const stats = db.prepare(
    'SELECT COUNT(*) AS total, SUM(completed_by IS NOT NULL) AS done FROM tasks WHERE category_id = ?'
  ).get(c.id);
  return {
    id: c.id, name: c.name, color: c.color, ownerId: c.owner_id, groupId: c.group_id,
    taskCount: Number(stats.total), doneCount: Number(stats.done || 0),
  };
};

const routes = [];
const route = (method, pattern, auth, handler) => {
  const names = [];
  const regex = new RegExp('^' + pattern.replace(/:(\w+)/g, (_, n) => { names.push(n); return '(\\d+)'; }) + '$');
  routes.push({ method, regex, names, auth, handler });
};

// --- hesap ---

route('POST', '/api/register', false, (body) => {
  const username = String(body.username || '').trim();
  const password = String(body.password || '');
  if (!/^[a-zA-Z0-9_.]{3,30}$/.test(username))
    throw new ApiError(400, 'Kullanıcı adı 3-30 karakter olmalı; harf, rakam, nokta ve alt çizgi kullanılabilir.');
  if (password.length < 6) throw new ApiError(400, 'Şifre en az 6 karakter olmalı.');
  if (db.prepare('SELECT 1 FROM users WHERE username = ?').get(username))
    throw new ApiError(409, 'Bu kullanıcı adı zaten alınmış.');
  const salt = crypto.randomBytes(16).toString('hex');
  const info = db.prepare(
    'INSERT INTO users (username, password_hash, salt, first_name, last_name, email, created_at) VALUES (?,?,?,?,?,?,?)'
  ).run(username, hashPassword(password, salt), salt,
        body.firstName || null, body.lastName || null, body.email || null, now());
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(Number(info.lastInsertRowid));
  return { token: signToken(user.id), user: publicUser(user) };
});

route('POST', '/api/login', false, (body) => {
  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(String(body.username || '').trim());
  if (!user || hashPassword(String(body.password || ''), user.salt) !== user.password_hash)
    throw new ApiError(401, 'Kullanıcı adı veya şifre hatalı.');
  return { token: signToken(user.id), user: publicUser(user) };
});

route('GET', '/api/me', true, (_body, user) => publicUser(user));

route('PUT', '/api/me', true, (body, user) => {
  db.prepare('UPDATE users SET first_name = ?, last_name = ?, email = ? WHERE id = ?')
    .run(body.firstName || null, body.lastName || null, body.email || null, user.id);
  // Ad değişince grup üyeleri listelerde yeni adı görsün.
  const audience = db.prepare('SELECT DISTINCT user_id FROM group_members WHERE group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)')
    .all(user.id).map((r) => r.user_id);
  notify([user.id, ...audience]);
  return publicUser(db.prepare('SELECT * FROM users WHERE id = ?').get(user.id));
});

route('PUT', '/api/me/password', true, (body, user) => {
  if (hashPassword(String(body.currentPassword || ''), user.salt) !== user.password_hash)
    throw new ApiError(403, 'Mevcut şifren hatalı.');
  const newPassword = String(body.newPassword || '');
  if (newPassword.length < 6) throw new ApiError(400, 'Yeni şifre en az 6 karakter olmalı.');
  const salt = crypto.randomBytes(16).toString('hex');
  db.prepare('UPDATE users SET password_hash = ?, salt = ? WHERE id = ?')
    .run(hashPassword(newPassword, salt), salt, user.id);
  return { ok: true };
});

route('DELETE', '/api/me', true, (_body, user) => {
  const founded = db.prepare('SELECT name FROM groups WHERE founder_id = ?').all(user.id);
  if (founded.length > 0)
    throw new ApiError(409,
      `Kurucusu olduğun grup(lar) var: ${founded.map((g) => g.name).join(', ')}. ` +
      'Hesabını silmeden önce bu grupları silmelisin; yoksa sahipsiz kalırlar.');
  const audience = db.prepare('SELECT DISTINCT user_id FROM group_members WHERE group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)')
    .all(user.id).map((r) => r.user_id);
  db.prepare('DELETE FROM tasks WHERE category_id IN (SELECT id FROM categories WHERE owner_id = ? AND group_id IS NULL)').run(user.id);
  db.prepare('DELETE FROM categories WHERE owner_id = ? AND group_id IS NULL').run(user.id);
  db.prepare('DELETE FROM group_members WHERE user_id = ?').run(user.id);
  db.prepare('DELETE FROM users WHERE id = ?').run(user.id);
  notify(audience.filter((id) => id !== user.id));
  return { ok: true };
});

// --- durum (tek istekte her şey: kullanıcı + gruplar + kategoriler) ---

route('GET', '/api/state', true, (_body, user) => {
  const groups = db.prepare(`
    SELECT g.* FROM groups g JOIN group_members gm ON gm.group_id = g.id
    WHERE gm.user_id = ? ORDER BY g.created_at
  `).all(user.id);
  const categories = db.prepare(`
    SELECT c.* FROM categories c
    WHERE (c.group_id IS NULL AND c.owner_id = ?)
       OR c.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
    ORDER BY c.created_at
  `).all(user.id, user.id);
  return {
    user: publicUser(user),
    groups: groups.map(groupJson),
    categories: categories.map(categoryJson),
  };
});

// --- gruplar ---

route('POST', '/api/groups', true, (body, user) => {
  const name = String(body.name || '').trim();
  if (!name) throw new ApiError(400, 'Grup adı boş olamaz.');
  const info = db.prepare('INSERT INTO groups (name, founder_id, invite_code, created_at) VALUES (?,?,?,?)')
    .run(name, user.id, makeInviteCode(), now());
  const groupId = Number(info.lastInsertRowid);
  db.prepare('INSERT INTO group_members (group_id, user_id, joined_at) VALUES (?,?,?)')
    .run(groupId, user.id, now());
  return groupJson(db.prepare('SELECT * FROM groups WHERE id = ?').get(groupId));
});

route('POST', '/api/groups/join', true, (body, user) => {
  const code = String(body.code || '').trim().toUpperCase();
  const group = db.prepare('SELECT * FROM groups WHERE invite_code = ?').get(code);
  if (!group) throw new ApiError(404, 'Bu davet koduna ait bir grup bulunamadı.');
  if (db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(group.id, user.id))
    throw new ApiError(409, 'Zaten bu grubun üyesisin.');
  db.prepare('INSERT INTO group_members (group_id, user_id, joined_at) VALUES (?,?,?)')
    .run(group.id, user.id, now());
  notify(groupMemberIds(group.id));
  return groupJson(group);
});

route('PUT', '/api/groups/:id', true, (body, user, params) => {
  const group = db.prepare('SELECT * FROM groups WHERE id = ?').get(params.id);
  if (!group) throw new ApiError(404, 'Grup bulunamadı.');
  if (group.founder_id !== user.id) throw new ApiError(403, 'Grup adını sadece kurucu değiştirebilir.');
  const name = String(body.name || '').trim();
  if (!name) throw new ApiError(400, 'Grup adı boş olamaz.');
  db.prepare('UPDATE groups SET name = ? WHERE id = ?').run(name, group.id);
  notify(groupMemberIds(group.id));
  return groupJson(db.prepare('SELECT * FROM groups WHERE id = ?').get(group.id));
});

route('DELETE', '/api/groups/:id', true, (_body, user, params) => {
  const group = db.prepare('SELECT * FROM groups WHERE id = ?').get(params.id);
  if (!group) throw new ApiError(404, 'Grup bulunamadı.');
  if (group.founder_id !== user.id) throw new ApiError(403, 'Grubu sadece kurucu silebilir.');
  const audience = groupMemberIds(group.id);
  db.prepare('DELETE FROM tasks WHERE category_id IN (SELECT id FROM categories WHERE group_id = ?)').run(group.id);
  db.prepare('DELETE FROM categories WHERE group_id = ?').run(group.id);
  db.prepare('DELETE FROM group_members WHERE group_id = ?').run(group.id);
  db.prepare('DELETE FROM groups WHERE id = ?').run(group.id);
  notify(audience);
  return { ok: true };
});

route('POST', '/api/groups/:id/leave', true, (_body, user, params) => {
  const group = db.prepare('SELECT * FROM groups WHERE id = ?').get(params.id);
  if (!group) throw new ApiError(404, 'Grup bulunamadı.');
  if (group.founder_id === user.id)
    throw new ApiError(403, 'Kurucu gruptan ayrılamaz; grup sahipsiz kalır. İstersen grubu silebilirsin.');
  const info = db.prepare('DELETE FROM group_members WHERE group_id = ? AND user_id = ?').run(group.id, user.id);
  if (info.changes === 0) throw new ApiError(404, 'Bu grubun üyesi değilsin.');
  notify([user.id, ...groupMemberIds(group.id)]);
  return { ok: true };
});

// --- kategoriler ---

route('POST', '/api/categories', true, (body, user) => {
  const name = String(body.name || '').trim();
  if (!name) throw new ApiError(400, 'Kategori adı boş olamaz.');
  const color = String(body.color || 'coral');
  let groupId = null;
  if (body.groupId != null) {
    groupId = Number(body.groupId);
    if (!db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(groupId, user.id))
      throw new ApiError(403, 'Bu grubun üyesi değilsin.');
  }
  const info = db.prepare('INSERT INTO categories (name, color, owner_id, group_id, created_at) VALUES (?,?,?,?,?)')
    .run(name, color, user.id, groupId, now());
  const cat = db.prepare('SELECT * FROM categories WHERE id = ?').get(Number(info.lastInsertRowid));
  notify(categoryAudience(cat).filter((id) => id !== user.id));
  return categoryJson(cat);
});

route('PUT', '/api/categories/:id', true, (body, user, params) => {
  const cat = getCategoryForUser(params.id, user.id);
  const isFounder = cat.group_id &&
    db.prepare('SELECT 1 FROM groups WHERE id = ? AND founder_id = ?').get(cat.group_id, user.id);
  if (cat.owner_id !== user.id && !isFounder)
    throw new ApiError(403, 'Kategoriyi sadece oluşturan kişi (veya grup kurucusu) düzenleyebilir.');
  const name = String(body.name ?? cat.name).trim();
  if (!name) throw new ApiError(400, 'Kategori adı boş olamaz.');
  db.prepare('UPDATE categories SET name = ?, color = ? WHERE id = ?')
    .run(name, String(body.color ?? cat.color), cat.id);
  notify(categoryAudience(cat));
  return categoryJson(db.prepare('SELECT * FROM categories WHERE id = ?').get(cat.id));
});

route('DELETE', '/api/categories/:id', true, (_body, user, params) => {
  const cat = getCategoryForUser(params.id, user.id);
  const isFounder = cat.group_id &&
    db.prepare('SELECT 1 FROM groups WHERE id = ? AND founder_id = ?').get(cat.group_id, user.id);
  if (cat.owner_id !== user.id && !isFounder)
    throw new ApiError(403, 'Kategoriyi sadece oluşturan kişi (veya grup kurucusu) silebilir.');
  db.prepare('DELETE FROM tasks WHERE category_id = ?').run(cat.id);
  db.prepare('DELETE FROM categories WHERE id = ?').run(cat.id);
  notify(categoryAudience(cat));
  return { ok: true };
});

// --- görevler ---

route('GET', '/api/categories/:id/tasks', true, (_body, user, params) => {
  const cat = getCategoryForUser(params.id, user.id);
  const rows = db.prepare(taskRowSql + ' WHERE t.category_id = ? ORDER BY (t.completed_by IS NOT NULL), t.created_at DESC')
    .all(cat.id);
  return rows.map(taskJson);
});

route('POST', '/api/categories/:id/tasks', true, (body, user, params) => {
  const cat = getCategoryForUser(params.id, user.id);
  const title = String(body.title || '').trim();
  if (!title) throw new ApiError(400, 'Görev başlığı boş olamaz.');
  const info = db.prepare(
    'INSERT INTO tasks (category_id, title, description, due_date, assigned_to, recurrence, created_by, created_at) VALUES (?,?,?,?,?,?,?,?)'
  ).run(cat.id, title, body.description || null, body.dueDate || null,
        validateAssignee(cat, body.assignedTo),
        validateRecurrence(body.recurrence, body.dueDate), user.id, now());
  logActivity(user, cat, 'created', title);
  notify(categoryAudience(cat), { categoryId: cat.id });
  const row = db.prepare(taskRowSql + ' WHERE t.id = ?').get(Number(info.lastInsertRowid));
  return taskJson(row);
});

route('PUT', '/api/tasks/:id', true, (body, user, params) => {
  const { task, cat } = getTaskForUser(params.id, user.id);
  if (task.created_by !== user.id)
    throw new ApiError(403, 'Görevi sadece oluşturan kişi düzenleyebilir.');
  const title = String(body.title ?? task.title).trim();
  if (!title) throw new ApiError(400, 'Görev başlığı boş olamaz.');
  const newDue = 'dueDate' in body ? (body.dueDate || null) : task.due_date;
  const newRecurrence = 'recurrence' in body
    ? validateRecurrence(body.recurrence || null, newDue)
    : validateRecurrence(task.recurrence, newDue);
  db.prepare('UPDATE tasks SET title = ?, description = ?, due_date = ?, assigned_to = ?, recurrence = ? WHERE id = ?')
    .run(title,
         'description' in body ? (body.description || null) : task.description,
         newDue,
         'assignedTo' in body ? validateAssignee(cat, body.assignedTo) : task.assigned_to,
         newRecurrence,
         task.id);
  notify(categoryAudience(cat), { categoryId: cat.id });
  return taskJson(db.prepare(taskRowSql + ' WHERE t.id = ?').get(task.id));
});

route('POST', '/api/tasks/:id/complete', true, (_body, user, params) => {
  const { task, cat } = getTaskForUser(params.id, user.id);
  // Zaten tamamlanmışsa ilk tamamlayanın emeği korunur; sessizce aynen döner.
  if (!task.completed_by) {
    // Tekrarlayan görevde tekrar bilgisi yeni oluşan göreve taşınır; tamamlanan
    // kopya sıradan görev olur (geri alınırsa çift oluşmasın diye).
    db.prepare('UPDATE tasks SET completed_by = ?, completed_at = ?, recurrence = NULL WHERE id = ?')
      .run(user.id, now(), task.id);
    if (task.recurrence && task.due_date) {
      db.prepare(
        'INSERT INTO tasks (category_id, title, description, due_date, assigned_to, recurrence, created_by, created_at) VALUES (?,?,?,?,?,?,?,?)'
      ).run(task.category_id, task.title, task.description,
            nextDueDate(task.due_date, task.recurrence),
            task.assigned_to, task.recurrence, task.created_by, now());
    }
    logActivity(user, cat, 'completed', task.title);
    notify(categoryAudience(cat), { categoryId: cat.id });
  }
  return taskJson(db.prepare(taskRowSql + ' WHERE t.id = ?').get(task.id));
});

route('POST', '/api/tasks/:id/uncomplete', true, (_body, user, params) => {
  const { task, cat } = getTaskForUser(params.id, user.id);
  if (!task.completed_by) return taskJson(db.prepare(taskRowSql + ' WHERE t.id = ?').get(task.id));
  if (task.completed_by !== user.id) {
    const who = db.prepare('SELECT * FROM users WHERE id = ?').get(task.completed_by);
    throw new ApiError(403, `Bu görevi ${who ? displayName(who) : 'başkası'} tamamladı; geri almayı sadece o yapabilir.`);
  }
  db.prepare('UPDATE tasks SET completed_by = NULL, completed_at = NULL WHERE id = ?').run(task.id);
  logActivity(user, cat, 'uncompleted', task.title);
  notify(categoryAudience(cat), { categoryId: cat.id });
  return taskJson(db.prepare(taskRowSql + ' WHERE t.id = ?').get(task.id));
});

route('DELETE', '/api/tasks/:id', true, (_body, user, params) => {
  const { task, cat } = getTaskForUser(params.id, user.id);
  if (task.created_by !== user.id)
    throw new ApiError(403, 'Görevi sadece oluşturan kişi silebilir.');
  db.prepare('DELETE FROM tasks WHERE id = ?').run(task.id);
  logActivity(user, cat, 'deleted', task.title);
  notify(categoryAudience(cat), { categoryId: cat.id });
  return { ok: true };
});

// Açık ve son tarihli görevler: hatırlatıcı planlama ve widget için.
route('GET', '/api/tasks/upcoming', true, (_body, user) => {
  const rows = db.prepare(`
    SELECT t.id, t.title, t.due_date, t.assigned_to, c.id AS category_id, c.name AS category_name
    FROM tasks t JOIN categories c ON c.id = t.category_id
    WHERE t.completed_by IS NULL AND t.due_date IS NOT NULL
      AND ((c.group_id IS NULL AND c.owner_id = ?)
           OR c.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?))
    ORDER BY t.due_date LIMIT 100
  `).all(user.id, user.id);
  return rows.map((r) => ({
    id: r.id, title: r.title, dueDate: r.due_date, assignedTo: r.assigned_to,
    categoryId: r.category_id, categoryName: r.category_name,
  }));
});

// --- etkinlik akışı ---

route('GET', '/api/activity', true, (_body, user) => {
  const rows = db.prepare(`
    SELECT a.*, c.name AS category_name, c.color AS category_color, g.name AS group_name
    FROM activity a
    JOIN categories c ON c.id = a.category_id
    LEFT JOIN groups g ON g.id = c.group_id
    WHERE (c.group_id IS NULL AND c.owner_id = ?)
       OR c.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
    ORDER BY a.id DESC LIMIT 50
  `).all(user.id, user.id);
  return rows.map((a) => ({
    id: a.id,
    actorId: a.actor_id,
    actorName: a.actor_name,
    action: a.action,
    taskTitle: a.task_title,
    categoryName: a.category_name,
    categoryColor: a.category_color,
    groupName: a.group_name,
    createdAt: a.created_at,
  }));
});

// ------------------------------------------------------------------ http sunucu

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 1_000_000) { reject(new ApiError(413, 'İstek çok büyük.')); req.destroy(); }
    });
    req.on('end', () => {
      if (!data) return resolve({});
      try { resolve(JSON.parse(data)); }
      catch { reject(new ApiError(400, 'Geçersiz JSON.')); }
    });
    req.on('error', reject);
  });
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    });
    return res.end();
  }

  // SSE: canlı senkronizasyon kanalı. Token yalnızca Authorization başlığıyla
  // alınır — URL'de taşınan token'lar log'lara/proxy'lere sızar.
  if (req.method === 'GET' && url.pathname === '/api/events') {
    const uid = verifyToken((req.headers.authorization || '').replace(/^Bearer /, ''));
    if (!uid) return sendJson(res, 401, { error: 'Oturum geçersiz. Yeniden giriş yap.' });
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });
    res.write(': bağlandı\n\n');
    sseSubscribe(uid, res);
    return;
  }

  try {
    for (const r of routes) {
      if (r.method !== req.method) continue;
      const m = url.pathname.match(r.regex);
      if (!m) continue;
      const params = {};
      r.names.forEach((n, i) => { params[n] = Number(m[i + 1]); });
      let user = null;
      if (r.auth) {
        const uid = verifyToken((req.headers.authorization || '').replace(/^Bearer /, ''));
        if (uid) user = db.prepare('SELECT * FROM users WHERE id = ?').get(uid);
        if (!user) return sendJson(res, 401, { error: 'Oturum geçersiz. Yeniden giriş yap.' });
      }
      const body = ['POST', 'PUT', 'PATCH'].includes(req.method) ? await readBody(req) : {};
      const result = await r.handler(body, user, params);
      return sendJson(res, 200, result);
    }
    sendJson(res, 404, { error: 'Böyle bir uç nokta yok.' });
  } catch (err) {
    if (err instanceof ApiError) return sendJson(res, err.status, { error: err.message });
    console.error(err);
    sendJson(res, 500, { error: 'Sunucuda beklenmeyen bir hata oluştu.' });
  }
});

server.listen(PORT, () => {
  console.log(`Pano sunucusu çalışıyor: http://localhost:${PORT}`);
});
