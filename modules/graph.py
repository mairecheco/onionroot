#!/usr/bin/env python3
"""
OnionRoot — modules/graph.py
Analyze the local dataset and build a network graph of onion service relationships.
Exports to JSON, CSV, or GEXF (Gephi) format.
"""

import sys
import os
import json
import collections
import csv
import argparse
from datetime import datetime

# ── Colors ──────────────────────────────────────────────────────────────────
P  = '\033[0m\033[35m'
LP = '\033[0m\033[1m\033[35m'
G  = '\033[0m\033[32m'
R  = '\033[0m\033[1m\033[31m'
Y  = '\033[0m\033[33m'
C  = '\033[0m\033[36m'
W  = '\033[0m\033[37m'
DIM= '\033[2m'
NC = '\033[0m'

def p_hit(msg):   print(f"  {G}[+]{NC} {msg}")
def p_info(msg):  print(f"  {C}[~]{NC} {msg}")
def p_warn(msg):  print(f"  {Y}[!]{NC} {msg}")
def p_err(msg):   print(f"  {R}[✗]{NC} {msg}", file=sys.stderr)
def p_kv(k, v):   print(f"  {DIM}  {k:<22}{NC}{W}{v}{NC}")
def p_div():       print(f"  {P}  {'─'*50}{NC}")
def p_sec(title):
    print(f"\n  {P}{'─'*52}{NC}")
    print(f"  {LP}  {title}{NC}")
    print(f"  {P}{'─'*52}{NC}\n")


# ── Dataset loader ───────────────────────────────────────────────────────────
def load_dataset(path: str) -> list[dict]:
    entries = []
    if not os.path.exists(path):
        p_warn(f"Dataset not found: {path}")
        p_warn("Run: onionroot crawl  or  onionroot dataset build")
        sys.exit(1)
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return entries


# ── Graph builder ────────────────────────────────────────────────────────────
def build_graph(entries: list[dict]) -> dict:
    """
    Returns:
        nodes: {onion: {title, server, source, discovered, degree}}
        edges: [(source_onion, target_onion)]
    """
    nodes = {}
    edges = []
    edge_set = set()

    for entry in entries:
        onion = entry.get('onion', '')
        if not onion:
            continue
        nodes[onion] = {
            'title':      entry.get('title', 'unknown'),
            'server':     entry.get('server', 'unknown'),
            'source':     entry.get('source', 'unknown'),
            'discovered': entry.get('discovered', ''),
            'status':     entry.get('status', 0),
            'degree':     0,
        }

    for entry in entries:
        src = entry.get('onion', '')
        for dst in entry.get('links', []):
            if not dst or src == dst:
                continue
            key = (src, dst)
            if key not in edge_set:
                edge_set.add(key)
                edges.append(key)
                if src in nodes:
                    nodes[src]['degree'] += 1
                if dst in nodes:
                    nodes[dst]['degree'] += 1
                elif dst not in nodes:
                    # Add referenced node not in dataset
                    nodes[dst] = {
                        'title': '(referenced, not crawled)',
                        'server': 'unknown',
                        'source': 'link',
                        'discovered': '',
                        'status': 0,
                        'degree': 1,
                    }

    return {'nodes': nodes, 'edges': edges}


# ── Stats ────────────────────────────────────────────────────────────────────
def print_stats(graph: dict):
    nodes = graph['nodes']
    edges = graph['edges']

    n = len(nodes)
    e = len(edges)
    density = (2 * e) / (n * (n - 1)) if n > 1 else 0

    p_sec("Network Graph Statistics")
    p_kv("Nodes (services)", str(n))
    p_kv("Edges (links)",    str(e))
    p_kv("Graph density",   f"{density:.6f}")

    # Degree distribution
    degrees = [v['degree'] for v in nodes.values()]
    if degrees:
        p_kv("Max degree",    str(max(degrees)))
        p_kv("Avg degree",    f"{sum(degrees)/len(degrees):.2f}")
        isolated = sum(1 for d in degrees if d == 0)
        p_kv("Isolated nodes",str(isolated))

    # Top connected nodes
    p_sec("Top 10 Most Connected Services")
    top = sorted(nodes.items(), key=lambda x: x[1]['degree'], reverse=True)[:10]
    for i, (onion, data) in enumerate(top, 1):
        title = data['title'][:45]
        print(f"  {G}[{i:02d}]{NC}  {LP}{onion}{NC}")
        print(f"         {DIM}Title:   {NC}{W}{title}{NC}")
        print(f"         {DIM}Degree:  {NC}{W}{data['degree']}{NC}")
        print()

    # Server breakdown
    p_sec("Server Distribution")
    server_counts = collections.Counter(v['server'] for v in nodes.values())
    for srv, cnt in server_counts.most_common(10):
        bar = '█' * min(cnt, 30)
        print(f"  {G}▸{NC}  {W}{srv:<20}{NC}  {P}{bar}{NC}  {DIM}{cnt}{NC}")

    # Source breakdown
    p_sec("Discovery Sources")
    source_counts = collections.Counter(v['source'] for v in nodes.values())
    for src, cnt in source_counts.most_common():
        print(f"  {G}▸{NC}  {W}{src:<20}{NC}  {DIM}{cnt} services{NC}")


# ── Exporters ────────────────────────────────────────────────────────────────
def export_json(graph: dict, outfile: str):
    data = {
        'generated': datetime.utcnow().isoformat() + 'Z',
        'nodes': [{'id': k, **v} for k, v in graph['nodes'].items()],
        'edges': [{'source': s, 'target': t} for s, t in graph['edges']],
    }
    with open(outfile, 'w') as f:
        json.dump(data, f, indent=2)
    p_hit(f"JSON graph saved: {outfile}")


def export_csv(graph: dict, nodes_file: str, edges_file: str):
    # Nodes CSV
    with open(nodes_file, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['id','title','server','source','discovered','status','degree'])
        w.writeheader()
        for onion, data in graph['nodes'].items():
            w.writerow({'id': onion, **data})
    p_hit(f"Nodes CSV saved: {nodes_file}")

    # Edges CSV
    with open(edges_file, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['source','target'])
        w.writeheader()
        for src, tgt in graph['edges']:
            w.writerow({'source': src, 'target': tgt})
    p_hit(f"Edges CSV saved: {edges_file}")


def export_gexf(graph: dict, outfile: str):
    """Export in GEXF format for Gephi/Sigma.js visualization."""
    ts = datetime.utcnow().strftime('%Y-%m-%d')
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gexf xmlns="http://gexf.net/1.3" version="1.3">',
        f'  <meta lastmodifieddate="{ts}">',
        '    <creator>OnionRoot</creator>',
        '    <description>Onion Network Graph</description>',
        '  </meta>',
        '  <graph defaultedgetype="directed">',
        '    <attributes class="node">',
        '      <attribute id="0" title="title" type="string"/>',
        '      <attribute id="1" title="server" type="string"/>',
        '      <attribute id="2" title="degree" type="integer"/>',
        '    </attributes>',
        '    <nodes>',
    ]
    node_ids = {onion: str(i) for i, onion in enumerate(graph['nodes'])}
    for onion, data in graph['nodes'].items():
        nid = node_ids[onion]
        title = data['title'].replace('"','&quot;').replace('<','&lt;').replace('>','&gt;')
        lines.append(f'      <node id="{nid}" label="{onion}">')
        lines.append( '        <attvalues>')
        lines.append(f'          <attvalue for="0" value="{title}"/>')
        lines.append(f'          <attvalue for="1" value="{data["server"]}"/>')
        lines.append(f'          <attvalue for="2" value="{data["degree"]}"/>')
        lines.append( '        </attvalues>')
        lines.append( '      </node>')
    lines.append('    </nodes>')
    lines.append('    <edges>')
    for i, (src, tgt) in enumerate(graph['edges']):
        if src in node_ids and tgt in node_ids:
            lines.append(f'      <edge id="{i}" source="{node_ids[src]}" target="{node_ids[tgt]}"/>')
    lines.append('    </edges>')
    lines.append('  </graph>')
    lines.append('</gexf>')
    with open(outfile, 'w') as f:
        f.write('\n'.join(lines))
    p_hit(f"GEXF graph saved: {outfile}")


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        prog='onionroot graph',
        description='Analyze onion dataset and build a network graph'
    )
    parser.add_argument('--export', choices=['json','csv','gexf'], help='Export format')
    parser.add_argument('--output', '-o', default='', help='Output file path')
    parser.add_argument('--dataset', default='', help='Path to dataset.jsonl')
    args = parser.parse_args()

    dataset_path = args.dataset or os.path.join(
        os.environ.get('HOME', ''), '.onionroot', 'dataset.jsonl'
    )
    data_dir = os.path.dirname(dataset_path)
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')

    p_sec("OnionRoot — Network Graph")
    p_info(f"Dataset: {dataset_path}")

    entries = load_dataset(dataset_path)
    if not entries:
        p_warn("Dataset is empty. Run: onionroot crawl")
        sys.exit(0)

    p_info(f"Loaded {len(entries)} entries. Building graph...")
    graph = build_graph(entries)

    print_stats(graph)

    if args.export:
        fmt = args.export
        if fmt == 'json':
            out = args.output or os.path.join(data_dir, f'graph_{ts}.json')
            export_json(graph, out)
        elif fmt == 'csv':
            n_out = args.output or os.path.join(data_dir, f'graph_nodes_{ts}.csv')
            e_out = os.path.join(data_dir, f'graph_edges_{ts}.csv')
            export_csv(graph, n_out, e_out)
        elif fmt == 'gexf':
            out = args.output or os.path.join(data_dir, f'graph_{ts}.gexf')
            export_gexf(graph, out)

        print()
        p_div()
        p_info("Open GEXF files in Gephi or Sigma.js for visualization")
        p_div()
    else:
        print()
        p_div()
        p_info(f"Export: {C}onionroot graph --export json|csv|gexf{NC}")
        p_div()

    print()


if __name__ == '__main__':
    main()
