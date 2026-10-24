# 怎么把这个目录推到 GitHub

已确认：当前会话的 GitHub 连接器只有读权限（创建仓库、fork、写文件全部返回
`403 Resource not accessible by integration`），所以本地准备好后需要你点一下。

两种方式，任选其一。

---

## 方式一：连上 GitHub 连接器后交给我（推荐）

在对话里让我重新连接 GitHub 并授予仓库写权限，之后我可以直接把文件推上去、
建 Release、贴说明。适合不想碰命令行的场景。

---

## 方式二：自己推（3 条命令）

目标仓库：`https://github.com/ruiRun0916/android_kernel_xiaomi_sm8350_miyume`

### 1. 进入目录并初始化

```bash
cd ~/WorkBuddy/2026-10-17-11-03-30/star-droidspaces-kernel
git init -b main
git add -A
git commit -m "droidspaces: star 5.4.302 kernel build docs, patches, config and AK3 package"
```

### 2. 加远程

```bash
git remote add origin https://github.com/ruiRun0916/android_kernel_xiaomi_sm8350_miyume.git
```

### 3. 推送

推到独立分支最稳妥，不会污染上游代码：

```bash
git push -u origin main:droidspaces
```

> 如果你想把内容直接放在默认分支上，用 `git push -u origin main`（要看那个仓库
> 的默认分支名是 `main` 还是 `Stable4`）。

认证方式任选：
- GitHub CLI：`gh auth login` 后 `gh auth setup-git`
- HTTPS + PAT：推送时用户名填 `ruiRun0916`，密码填 Personal Access Token（需 `repo` 权限）
- GitHub Desktop：直接 Add local repository 再 Publish

---

## 推上去之后：把刷机包做成 Release

仓库里的 `artifacts/AK3-Star-Stable4-Droidspaces-v2.zip`（约 25MB）已经提交进 git，
但更规范的做法是放到 Release：

1. 仓库页右侧 **Releases** -> **Draft a new release**
2. Tag 填 `v2`，标题填 `Stable4 Droidspaces v2 (star)`
3. 说明直接从根目录 `RELEASE_NOTES.md` 复制
4. 附件拖入 `artifacts/AK3-Star-Stable4-Droidspaces-v2.zip`
5. 发布，把下载链接替换进 README 的「刷入」章节

如需一并放出 fastboot 用的 boot.img（94MB），也作为 Release 附件上传，不要提交进 git
（接近单文件 100MB 限制）。
