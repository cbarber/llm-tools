---
title: Exec Demo
author: Craig Barber
---

Basic Execution
===

Simple echo command:

```bash +exec
echo "Hello from live execution!"
```

<!-- pause -->

Show environment:

```bash +exec
echo "Current directory: $PWD"
echo "User: $USER"
echo "In sandbox: ${IN_AGENT_SANDBOX:-no}"
```

<!-- end_slide -->

Sandbox Demo
===

Try to access home directory:

```bash +exec
touch ~/test-from-presentation.txt 2>&1 || echo "Blocked as expected"
```

<!-- pause -->

Try dangerous command:

```bash +exec
rm -rf ~/ 2>&1 || echo "Sandbox protected!"
```

<!-- end_slide -->

Named Output
===

Execute and place output elsewhere:

```bash +exec +id:demo_output
echo "This output can be referenced elsewhere"
date
```

<!-- pause -->

The output appears here:

<!-- snippet_output: demo_output -->

<!-- end_slide -->
