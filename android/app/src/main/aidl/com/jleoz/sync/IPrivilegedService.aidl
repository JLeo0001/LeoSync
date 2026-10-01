package com.jleoz.sync;

// Shizuku UserService：跑在 shell（ADB）/root 身份的隔离进程里，
// 供 Dart 侧执行 appops / pm 等特权命令。返回 JSON：
// {"exit":0,"out":"...","err":"..."}
interface IPrivilegedService {
    String run(in String[] cmd);
}
