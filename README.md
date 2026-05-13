# Firebase Studio SSH Workspace

This workspace automatically sets up an SSH reverse tunnel to a relay server.

## Connection

Recommended client UX after adding SSH config:

```bash
ssh -J idx.yaoshen.de5.net:2022 default-13412936
```

Or, if `Port 2022` is set in the `Host idx.yaoshen.de5.net` block:

```bash
ssh -J idx.yaoshen.de5.net default-13412936
```

Without SSH config, use the explicit form:

```bash
ssh -J user@117.31.178.161:2022 user@default-13412936
```

## Bootstrap

The workspace automatically:
1. Writes the shared sish SSH key to `~/.ssh/sish`
2. Starts local `sshd` on `127.0.0.1:2222`
3. Starts a sish TCP alias tunnel to `117.31.178.161:2022`
4. Exposes local SSH as sish alias `default-13412936:22`

## Logs

Check tunnel status:
```bash
cat ~/.ssh/sish.log
ps aux | grep ssh
```

## Key names

Use two shared keys for all workspaces:

```text
sish   -> logs into sish/jump server
client -> logs into the workspace sshd behind the alias
```

## Optional SSH config

Add this to `~/.ssh/config` if you want official-style short commands:

```sshconfig
Host idx.yaoshen.de5.net
  HostName 117.31.178.161
  Port 2022
  User user
  IdentityFile ~/.ssh/sish
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host default-13412936
  User user
  IdentityFile ~/.ssh/client
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

Then either of these works:

```bash
ssh -J idx.yaoshen.de5.net:2022 default-13412936
ssh -J idx.yaoshen.de5.net default-13412936
```
