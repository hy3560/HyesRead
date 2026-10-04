import { invoke, readValue, updateValue } from "./platform";

export type CatalogSource = { url: string; title: string };
export const CATALOG_STORE = "hyes_catalogs.json";
let migration: Promise<CatalogSource[]> | undefined;

export function migrateCatalogSources(): Promise<CatalogSource[]> {
  if (migration) return migration;
  const operation = (async () => {
    const sources = await readValue<CatalogSource[]>(CATALOG_STORE, "sources", []);
    const migrated = new Map<string, string>();
    for (const source of sources) {
      const url = new URL(source.url);
      if (url.username || url.password) {
        migrated.set(source.url, await invoke<string>("save_opds_credentials", { url: source.url }));
      }
    }
    if (!migrated.size) return sources;
    return updateValue<CatalogSource[]>(CATALOG_STORE, "sources", [], current => {
      const normalized = new Map<string, CatalogSource>();
      for (const source of current) {
        const url = migrated.get(source.url) ?? source.url;
        normalized.set(url, { ...source, url });
      }
      return Array.from(normalized.values());
    });
  })();
  migration = operation;
  void operation.finally(() => { if (migration === operation) migration = undefined; }).catch(() => undefined);
  return operation;
}
