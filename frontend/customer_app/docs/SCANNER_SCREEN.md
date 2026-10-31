# Kesor Scan

Updated 31 October 2026, Asia/Phnom_Penh.

The supplied ABA scanner image is a composition reference: immersive camera,
centered title and close action, four rounded viewfinder corners, two pill
controls, and a compact brand footer. Kesor uses its existing navy/gold palette,
Poppins/Google Sans with Khmer fallback, and local Kesor logo artwork. External
payment-network logos are omitted because the API accepts registered Kesor QRs.

`ScanQrScreen` owns the visual layout, while `ScanQrPanel` retains local decoding,
camera lifecycle, trusted image selection, validation, and transfer handoff.
`AccountsShell` displays the scanner directly, without the generic AppBar,
refresh actions, scrolling page padding, or bottom navigation.

- Camera preview fills the upper area and clips to rounded bottom corners.
- Gold corner artwork and the native detector use the same responsive scan rect.
- Flash follows the native torch state and is disabled when unavailable.
- Upload QR retains the JPG/PNG, 5 MB and 16-million-pixel limits.
- Permission/unsupported-QR errors retain image import and explicit scan retry.
- Close and Android Back return through the shell's existing navigation.
- Verified scans prefill the existing Transfer screen; scanning sends no payment.
- English/Khmer labels, safe areas, large text, portrait, landscape and tablet
  layouts are supported. This camera screen intentionally stays dark in both
  application themes for consistent visibility over the live camera.

Verification: 230 full Flutter tests passed; analysis found no issues.
`flutter test tool/scanner_visual_qa.dart --concurrency=1 --no-pub` passed,
rendering 12 combinations of phone, small phone, 2x Khmer text, landscape,
tablet and permission denial across both app themes with reduced motion.
The fixture also checks safe-area clearance, scan-window size, close callbacks,
camera stop and verified recipient handoff. Native camera hardware and personal
gallery selection still require physical-device acceptance.

Renders are ignored under `.local/qa/scanner/`. Test camera frames are fixtures,
not photographs from the user's device. Backend/API/database behavior is unchanged.
