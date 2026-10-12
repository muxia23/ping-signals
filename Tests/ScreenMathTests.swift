import CoreGraphics
import Testing
@testable import PingCore

@Suite struct ScreenMathTests {
  // Primary screen 1440×900 at AppKit origin (0,0); a second screen 1920×1080 to its right, bottoms aligned.
  let primaryHeight: CGFloat = 900
  let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

  @Test func globalToAppKit() {
    #expect(ScreenMath.appKitPoint(fromGlobal: CGPoint(x: 10, y: 20), primaryHeight: primaryHeight) == CGPoint(x: 10, y: 880))
  }

  @Test func appKitToGlobal() {
    #expect(ScreenMath.globalPoint(fromAppKit: CGPoint(x: 10, y: 880), primaryHeight: primaryHeight) == CGPoint(x: 10, y: 20))
  }

  @Test func localPointInSecondScreen() {
    // Global (1500, 100): 100 pt below the top of the second screen (whose top is at global y = 900 - 1080 = -180).
    let local = ScreenMath.localPoint(fromGlobal: CGPoint(x: 1500, y: 100), screenFrame: second, primaryHeight: primaryHeight)
    #expect(local == CGPoint(x: 60, y: 800))
  }

  @Test func globalRectOfScreen() {
    #expect(ScreenMath.globalRect(ofScreenFrame: second, primaryHeight: primaryHeight) == CGRect(x: 1440, y: -180, width: 1920, height: 1080))
  }
}
