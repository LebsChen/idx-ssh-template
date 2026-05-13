# Firebase Studio SSH Workspace

This workspace automatically sets up an SSH reverse tunnel to a relay server.

## Connection

```bash
ssh -o ProxyCommand="ssh -i relay_key -W %h:%p -p 2222 app@117.31.178.161" -p 2002 user@127.0.0.1
```

## Bootstrap

The workspace automatically:
1. Fetches the relay SSH key from `https://idx.yaoshen.de5.net/bootstrap/relay_ed25519`
2. Starts an SSH reverse tunnel to `117.31.178.161:2222`
3. Exposes local SSH (port 22) on relay port 2002

## Logs

Check tunnel status:
```bash
cat ~/.ssh/tunnel.log
ps aux | grep ssh
```
