#!/usr/bin/env python3
"""Make opencode's agents from Claude Code's, so there is one set to edit.

    python3 tool/sync_agents.py

Reads .claude/agents/*.md (the source: edit those) and writes
.opencode/agents/<name>.md with the same instructions and opencode's
frontmatter. The model for each tier is set here: Claude's "haiku" agents
run on the local model, its "sonnet" agents on Grok. The orchestrator
(.opencode/agents/orchestrator.md) is opencode's own and is left alone.
"""
import glob
import os
import re

TIER = {
    'haiku': 'locals/locals/qwen3.5-2b',  # free: finding, checking, notes
    'sonnet': 'xai/grok-4.7',             # coding, tests, review
}
READ_ONLY = {'Edit', 'Write'}

root = os.path.join(os.path.dirname(__file__), '..')
out = os.path.join(root, '.opencode', 'agents')
os.makedirs(out, exist_ok=True)
for path in sorted(glob.glob(os.path.join(root, '.claude', 'agents', '*.md'))):
    text = open(path, encoding='utf-8').read()
    m = re.match(r'---\n(.*?)\n---\n(.*)', text, re.S)
    assert m, path
    head = dict(line.split(': ', 1) for line in m.group(1).splitlines())
    tools = {t.strip() for t in head.get('tools', '').split(',')}
    deny = ['task', 'question']
    if not tools & READ_ONLY:
        deny.append('edit')
    if 'Bash' not in tools:
        deny.append('bash')
    if not tools & {'WebFetch', 'WebSearch'}:
        deny += ['webfetch', 'websearch']
    front = ['---', f"description: {head['description']}", 'mode: all', f"model: {TIER[head['model']]}", 'permission:']
    # said outright, so a same-named agent in the global config can't
    # take away what this one needs
    allow = ['skill'] + (['bash'] if 'Bash' in tools else []) + (['edit'] if tools & READ_ONLY else [])
    front += [f'  {d}: deny' for d in deny] + [f'  {a}: allow' for a in allow] + ['---']
    name = head['name']
    with open(os.path.join(out, f'{name}.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(front) + '\n<!-- Made by tool/sync_agents.py from .claude/agents: edit that file. -->\n' + m.group(2))
    print(name, '->', TIER[head['model']])
