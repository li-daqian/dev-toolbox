# dev-toolbox
Installation and configuration of personal developer tools.

## Installation (Ubuntu)
```bash
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/bootstrap.sh?$(date +%s)" | sh
```

## Cleanup Disk (Ubuntu)
```bash
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/ubuntu/cleanup-disk.sh?$(date +%s)" | sh
```

## GitHub CLI (gh, Ubuntu)
```bash
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/ubuntu/install-gh.sh?$(date +%s)" | bash
```

## CPU Thermal Watch (Special Ubuntu Workaround)
For specific Intel laptop cases where Linux is stuck at unusually low CPU package power and the bottleneck is traced to the `processor_thermal` platform thermal chain.

```bash
bash ubuntu/cpu-thermal-watch/install.sh
```

Details:
- [ubuntu/cpu-thermal-watch/README.md](./ubuntu/cpu-thermal-watch/README.md)

## oh-my-zsh
```bash
curl -fsSL  "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/oh-my-zsh/install.sh?$(date +%s)" | sh
```

## rime (Only for linux)
```bash
curl -fsSL  "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/install.sh?$(date +%s)" | sh
```
