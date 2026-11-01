import Combine

/// Plain `ObservableObject` box for small pieces of view-local state. The CommandLineTools
/// toolchain this project builds with has no `SwiftUIMacros` plugin binary (that ships
/// inside Xcode.app), so the macro-based `@State` property wrapper fails to compile here.
/// `@StateObject` predates that macro and works fine, so view-local state is kept in one of
/// these instead.
final class StateBox<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
