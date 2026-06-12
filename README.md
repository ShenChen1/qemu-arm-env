# qemu-arm-env

轻量、无状态、可复原的 AArch64 虚拟开发环境。

## 架构

```
Host (x86_64)                          Guest (ARM64 / QEMU virt)
┌──────────────────────┐               ┌──────────────────────┐
│  Cross-compile       │   virtio-blk  │  Debian bookworm     │
│  linux/ (submodule)  │──────────────▶│  minbase (~50MB)     │
│                      │               │                      │
│  ./share/            │◀── virtio-9p ─│  /mnt/host/          │
│                      │               │                      │
│  GDB (tcp::26000)    │◀── gdbstub ──▶│  gdbserver / kprobes │
│  ssh -p 2222         │◀── user-net ──│  sshd                │
└──────────────────────┘               └──────────────────────┘
```

## 快速开始

```bash
# 1. 克隆（含内核子模块，~2GB）
git clone --recurse-submodules <repo-url>
cd qemu-arm-env

# 2. 安装宿主机依赖
sudo apt install qemu-system-aarch64 qemu-user-binfmt \
    gcc-aarch64-linux-gnu debootstrap

# 3. 一键构建 + 启动
make all    # 构建内核 + rootfs（首次 ~10min）
make qemu   # 无状态启动
```

## 内核配置

基于 `defconfig`，通过 `scripts/kernel.config` 精剪（启用项 4768 → 579，**-88%**）

## Rootfs

Debian bookworm minbase + 预装工具

## 典型工作流

```bash
# 9p 共享：宿主机 → VM
cp my-module.ko ./share/
# VM 内
insmod /mnt/host/my-module.ko

# 无状态：重启即还原。需要持久化时：
# 方式一：Ctrl-A c → commit all
# 方式二：make qemu-persist
```

## License

MIT
