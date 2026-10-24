# Git / GitHub 身份区分

## 现在的配置

本仓库（仅 local，不动全局）：

~~~text
user.name  = VX Agent
user.email = vx-agent@users.noreply.github.com
~~~

验证：

~~~powershell
git config --get user.name
git config --get user.email
git var GIT_AUTHOR_IDENT
~~~

之后由 agent 创建的普通 commit 显示为 `VX Agent <vx-agent@users.noreply.github.com>`，与 `lagudomeze <lagudomeze@163.com>` 区分开。

## 为什么 GitHub 上仍可能看起来是同一个账号

`git config` 只改 **commit 的 author/committer 元数据**，不改登录身份。

- PR、评论、merge 按钮、`gh pr merge` 都使用当前 gh token；
- 当前 token 属于 `lagudomeze`，所以 merge commit 的 author 仍是 `lagudomeze`；
- GitHub 不会因为 author email 是 `vx-agent@...` 就显示成另一个账号；它只是“未关联邮箱”的提交。

因此：

- 普通 commit：可以区分（VX Agent vs lagudomeze）；
- PR/merge/issue 评论：仍是 lagudomeze，除非换 token/账号。

## 如果要彻底分成两个账号

1. 新建一个 GitHub 机器账号（例如 `lagudomeze-vx-agent`）。
2. 把该账号加为本仓库 collaborator（Write 权限）。
3. 给机器账号生成 fine-grained PAT，或单独 SSH key。
4. 在 agent 环境用该账号登录：
   ~~~powershell
   gh auth login
   gh auth switch
   ~~~
5. 把机器账号的 noreply email 设为本仓库 user.email。
6. 这样 PR/merge/评论都会显示为机器账号。

注意：不要在两个身份之间混用同一个 PAT；否则 GitHub 仍按 token 所属账号记录操作。

## 建议的使用约定

- agent 的 commit 用 `VX Agent`，PR 标题/正文可加 `[agent]` 前缀；
- 人工提交保持 `lagudomeze`；
- merge 由谁执行就显示谁：如果希望 merge 也归 agent，必须用 agent token 执行；
- 不重写已有历史，只对之后的提交生效。
