import SwiftUI

struct SettingsView: View {
  @Bindable var model: SettingsModel

  var body: some View {
    TabView {
      TriggerTab(model: model).tabItem { Label("Trigger", systemImage: "cursorarrow.click.2") }
      Text("").tabItem { Label("Wheel", systemImage: "circle.grid.cross") }        // Task 7
      PingsSoundTab(model: model).tabItem { Label("Pings & Sound", systemImage: "speaker.wave.2") }
      Text("").tabItem { Label("Actions", systemImage: "bolt") }                   // Task 8
      GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
    }
    .frame(width: 620, height: 560)
  }
}
