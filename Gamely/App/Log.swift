import os

/// Gamely's unified-log channel. Read with:
/// `log stream --predicate 'subsystem == "com.gamely.app"'`
let log = Logger(subsystem: "com.gamely.app", category: "app")
