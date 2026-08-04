import QRCode from "qrcode";

// Generates a QR code as a base64 data URI — no external service call, no
// stored image file, just computed on demand whenever an LOA is viewed.
export async function generateQrDataUrl(text: string): Promise<string> {
  return QRCode.toDataURL(text, { width: 220, margin: 1 });
}
