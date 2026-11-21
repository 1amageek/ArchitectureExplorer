#include "ArchitectureSignals.h"
#include <signal.h>
static volatile sig_atomic_t received = 0;
static void handle_signal(int value) { received = value; }
void ae_install_signal_handlers(void) {
    struct sigaction action = {0};
    action.sa_handler = handle_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGINT, &action, 0);
    sigaction(SIGTERM, &action, 0);
}
int ae_signal_received(void) { return received; }
