import SwiftUI
import CoreImage.CIFilterBuiltins
import VisionKit

// Davet kodunun QR hali: kod elle yazmak yerine gösterip okutmak için.
struct InviteQR: View {
    let code: String

    var body: some View {
        if let image = Self.generate(code) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                .accessibilityLabel("Davet kodu QR: \(code)")
        }
    }

    private static func generate(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// Kamerayla QR okutup davet kodunu çıkarır. Desteklenmeyen cihazda
// (ör. simülatör) elle giriş öneren bir açıklama gösterir.
struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner { code in
                        onCode(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView {
                        Label("Kamera kullanılamıyor", systemImage: "camera")
                    } description: {
                        Text("Bu cihazda QR tarayıcı desteklenmiyor. Davet kodunu \"Davet Koduyla Katıl\" ile elle girebilirsin.")
                    }
                }
            }
            .navigationTitle("QR ile Katıl")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var handled = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let text = barcode.payloadStringValue,
                   let code = Self.extractInviteCode(text) {
                    handled = true
                    scanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }

        // QR içeriği ister çıplak kod ister paylaşım cümlesi olsun, 8 karakterlik kodu bul.
        static func extractInviteCode(_ text: String) -> String? {
            let upper = text.uppercased()
            guard let range = upper.range(of: "[A-Z2-9]{8}", options: .regularExpression) else { return nil }
            return String(upper[range])
        }
    }
}
