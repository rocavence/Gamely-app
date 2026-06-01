#pragma once
// Re-export the libnotify C API so Swift can call notify_register_dispatch /
// notify_get_state etc. (notify.h isn't part of the Swift Darwin module).
#include <notify.h>
