import SwiftUI

struct ClassroomURLEditAlertModifier: ViewModifier {
    @ObservedObject var manager: ClassroomURLManager

    func body(content: Content) -> some View {
        content.alert("クラスルームURLを設定", isPresented: $manager.isEditing) {
            TextField("URLを入力", text: $manager.temporaryURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("キャンセル", role: .cancel) {
                manager.cancel()
            }
            Button("保存") {
                manager.commit()
            }
            Button("クリア", role: .destructive) {
                manager.clear()
            }
        } message: {
            Text("Google Classroom・Zoom等のURLを入力してください. ClassroomのURLはアプリではなくブラウザから取得できます。")
        }
    }
}

extension View {
    func classroomURLEditAlert(manager: ClassroomURLManager) -> some View {
        self.modifier(ClassroomURLEditAlertModifier(manager: manager))
    }
}
