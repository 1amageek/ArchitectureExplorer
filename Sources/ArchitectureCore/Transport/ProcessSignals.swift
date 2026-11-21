import CArchitectureSignals

public enum ProcessSignals {
  public static func install() { ae_install_signal_handlers() }
  public static var interrupted: Bool { ae_signal_received() != 0 }
}
