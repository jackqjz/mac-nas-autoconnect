# Mac NAS 自动连接

员工请使用管理员提供的一页说明。首次在访达连接公司的 SMB 共享，并在钥匙串中记住自己的密码。安装程序可以从 [v2.2.0 发布页](https://github.com/jackqjz/mac-nas-autoconnect/releases/tag/v2.2.0) 下载。

在终端运行安装文件，传入公司提供的配置文件路径，随后按提示输入自己的 NAS 登录名。

```sh
/bin/bash ~/Downloads/install-nas.command "/path/to/company-nas.conf"
```

卸载时可在当前 Mac 上运行以下命令。

```sh
/bin/bash "$HOME/Library/Application Support/CompanyNASAutoMount/uninstall.sh"
```

用户登录后，监听进程订阅 macOS 网络配置变化和唤醒通知。登录、唤醒或网络变化时会合并短时间内的通知，再检查是否需要挂载。如果 DHCP 或网关缓存尚未就绪，会短暂补查。网络稳定时没有周期性定时检查。若仅 NAS 重启、网络始终没有变化，可用访达手动重连。旧版本用户再次运行新版安装命令即可升级。

管理员配置文件为一行空格分隔的五个值，依次是 NAS IPv4、NAS 网卡地址、网关 IPv4、网关网卡地址、URL 编码的共享名。网卡地址使用本机 arp 的小写格式。该文件由管理员按公司网络单独分发。

构建需要 macOS、Python 3 和 Xcode 命令行工具。在项目目录运行 `python3 build.py`，生成含 Intel 和 Apple 芯片挂载程序的安装文件。员工使用发布版无需编译。
