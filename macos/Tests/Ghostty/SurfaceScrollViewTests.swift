import AppKit
import Testing
@testable import Ghostty

struct SurfaceScrollViewTests {
    @Test func ignoresSubpixelScrollbarSyncDifferences() {
        // An NSClipView can quantize its bounds to the backing pixel grid.
        // A repeated core update must not send scroll(to:) back into AppKit.
        #expect(!SurfaceScrollView.needsScrollAdjustment(
            currentY: 100.0, targetY: 100.2, backingScale: 2
        ))
        #expect(SurfaceScrollView.needsScrollAdjustment(
            currentY: 100.0, targetY: 101.0, backingScale: 2
        ))
    }

    @Test func normalizesInvalidDisplayScale() {
        #expect(!SurfaceScrollView.needsScrollAdjustment(
            currentY: 20, targetY: 20.4, backingScale: 0
        ))
        #expect(SurfaceScrollView.needsScrollAdjustment(
            currentY: 20, targetY: 21.0, backingScale: 0
        ))
    }
}
