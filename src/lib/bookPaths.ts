export function mapBookPaths(previousRoot: string, currentRoot: string, previousPaths: string[], currentPaths: string[]): [string, string][] {
  const normalize = (path: string) => path.replaceAll("\\", "/").replace(/\/+$/, "").toLocaleLowerCase();
  const oldRoot = normalize(previousRoot);
  const newRoot = normalize(currentRoot);
  if (!oldRoot || !newRoot || oldRoot === newRoot) return [];

  const candidates = new Map<string, string[]>();
  for (const path of currentPaths) {
    const normalized = normalize(path);
    if (!normalized.startsWith(`${newRoot}/`)) continue;
    const relative = normalized.slice(newRoot.length + 1);
    candidates.set(relative, [...(candidates.get(relative) || []), path]);
  }

  const mappings: [string, string][] = [];
  for (const path of new Set(previousPaths)) {
    const normalized = normalize(path);
    if (!normalized.startsWith(`${oldRoot}/`)) continue;
    const relative = normalized.slice(oldRoot.length + 1);
    const matches = candidates.get(relative) || [];
    if (matches.length === 1) mappings.push([path, matches[0]]);
  }
  return mappings;
}
