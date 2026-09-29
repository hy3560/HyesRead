import { useCallback, useMemo } from "react";

const READER_URL = "/assets/web_reader/foliate-js/reader.html";

/** Creates a local reader URL for Foliate's bundled, offline-capable reading engine. */
export function useReaderEngine(filePath: string) {
  const format = useMemo(() => filePath.split(".").pop()?.toLowerCase() ?? "", [filePath]);
  const open = useCallback((frame: HTMLIFrameElement) => {
    if (!filePath) throw new Error("No book path was provided");
    const source = new URL(READER_URL, window.location.origin);
    source.searchParams.set("url", `https://asset.localhost/${filePath.replaceAll("\\", "/").split("/").map(encodeURIComponent).join("/")}`);
    frame.src = source.toString();
  }, [filePath]);

  return { open, format };
}
