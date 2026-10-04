export type LibrarySortMode = "title" | "author" | "recent";

export type LibraryBookLike = {
  title: string;
  author: string;
  path: string;
};

function normalizeSearchValue(value: string) {
  return value.normalize("NFKC").toLocaleLowerCase().replace(/\s+/g, " ").trim();
}

export function filterAndSortBooks<T extends LibraryBookLike>(
  books: readonly T[],
  bookAddedAt: Readonly<Record<string, number>>,
  query: string,
  sortMode: LibrarySortMode,
): T[] {
  const normalizedQuery = normalizeSearchValue(query);
  const terms = normalizedQuery ? normalizedQuery.split(" ").filter(Boolean) : [];
  const matches = books.filter(book => {
    if (!terms.length) return true;
    const searchText = normalizeSearchValue(`${book.title} ${book.author}`);
    return terms.every(term => searchText.includes(term));
  });

  return matches.sort((a, b) => sortMode === "title"
    ? a.title.localeCompare(b.title) || a.path.localeCompare(b.path)
    : sortMode === "author"
      ? a.author.localeCompare(b.author) || a.title.localeCompare(b.title) || a.path.localeCompare(b.path)
      : (bookAddedAt[b.path] ?? 0) - (bookAddedAt[a.path] ?? 0) || a.title.localeCompare(b.title) || a.path.localeCompare(b.path));
}
