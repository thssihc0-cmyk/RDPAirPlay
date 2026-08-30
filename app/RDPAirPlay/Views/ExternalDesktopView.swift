import SwiftUI

/// 第二屏专用：仅展示远程桌面（F-AP-02 / F-AP-05 同路帧）
struct ExternalDesktopView: View {
    @ObservedObject var controller: RDPSessionController

    var body: some View {
        RemoteDesktopView(controller: controller, interactionEnabled: true)
            .ignoresSafeArea()
            .background(Color.black)
    }
}
