#!/usr/bin/env python3
"""Read system symbol metadata through an existing trust relationship.

Research dependency: pymobiledevice3==11.40.2 in an isolated environment.
No new pairing, DDI mounting, root daemon suspension or Wallet file operations.
"""

import asyncio
import json
import logging
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def summarize_files(files):
    result = []
    for path, size in files:
        if not isinstance(path, str) or not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise ValueError("invalid_file_metadata")
        name = path.rsplit("/", 1)[-1]
        if name == "dyld" or re.fullmatch(r"dyld_shared_cache_arm64e?(?:\.[a-zA-Z0-9_]+)*", name):
            result.append({"name": name, "bytes": size})
    return {"fileCount": len(files), "systemFiles": result,
            "totalBytes": sum(size for _, size in files)}


def self_test():
    class XpcSize(int):
        pass

    summary = summarize_files([
        ("/PRIVATE-PATH/dyld_shared_cache_arm64e.01", XpcSize(1024)),
        ("/PRIVATE-PATH/PRIVATE-IDENTIFIER", 17),
    ])
    assert summary["fileCount"] == 2 and summary["totalBytes"] == 1041
    assert len(summary["systemFiles"]) == 1
    assert "PRIVATE" not in json.dumps(summary)
    for bad in [(None, 0), ("dyld", -1), ("dyld", True), ("dyld", "12")]:
        try:
            summarize_files([bad])
        except ValueError:
            pass
        else:
            raise AssertionError("invalid metadata was accepted")
    print("Symbol metadata validation and redaction passed.")


async def probe(serial, mode="list"):
    from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
    from pymobiledevice3.services.remote_fetch_symbols import RemoteFetchSymbolsService

    async with UserspaceRsdTunnel(serial=serial, autopair=False, remotepairing_fallback=False) as rsd:
        print(json.dumps({"stage": "tunnel_connected", "product": rsd.product_type,
                          "version": rsd.product_version, "build": rsd.product_build_version}), flush=True)
        async with RemoteFetchSymbolsService(rsd) as service:
            files = await service.get_dsc_file_list()
            summary = summarize_files([(item.file_path, item.file_size) for item in files])
            if mode == "headers":
                if rsd.product_build_version != "24A446":
                    raise ValueError("unexpected_target_build")
                selected = [(i, item) for i, item in enumerate(files)
                            if Path(item.file_path).name == "dyld_shared_cache_arm64e"]
                if not selected or sum(item.file_size for _, item in selected) > 128 * 1024 * 1024:
                    raise ValueError("unexpected_header_download_size")
                parents = sorted({str(Path(item.file_path).parent) for _, item in selected})
                downloaded = []
                for index, item in selected:
                    group = parents.index(str(Path(item.file_path).parent))
                    destination = ROOT / ".tmp/system-symbols/24A446" / f"cache-{group}" / "dyld_shared_cache_arm64e"
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    partial = destination.with_suffix(".part")
                    try:
                        received = 0
                        with partial.open("wb") as output:
                            async for chunk in service.service.iter_file_chunks(item.file_size, file_idx=index):
                                received += len(chunk)
                                if received > item.file_size:
                                    raise ValueError("oversized_transfer")
                                output.write(chunk)
                        if received != item.file_size:
                            raise ValueError("incomplete_transfer")
                        with partial.open("rb") as source:
                            if not source.read(16).startswith(b"dyld_v1"):
                                raise ValueError("unexpected_cache_header")
                        partial.replace(destination)
                    finally:
                        partial.unlink(missing_ok=True)
                    downloaded.append({"group": group, "bytes": received})
                    print(json.dumps({"stage": "header_downloaded", "group": group,
                                      "bytes": received}), flush=True)
                summary["downloadedHeaders"] = downloaded
        if mode == "cache":
            if rsd.product_build_version != "24A446" or summary["totalBytes"] > 8 * 1024 ** 3:
                raise ValueError("unexpected_cache_download")
            if shutil.disk_usage(ROOT).free < summary["totalBytes"] + 2 * 1024 ** 3:
                raise ValueError("insufficient_local_space")
            destination = ROOT / ".tmp/system-symbols/24A446/full"
            print(json.dumps({"stage": "cache_download", "bytes": summary["totalBytes"]}), flush=True)
            expected = [(item.file_path, item.file_size) for item in files]

            class CheckedSymbolsService(RemoteFetchSymbolsService):
                async def get_dsc_file_list(self):
                    current = await super().get_dsc_file_list()
                    if [(item.file_path, item.file_size) for item in current] != expected:
                        raise ValueError("symbol_list_changed")
                    return current

            # The downloader queries again: enforce the same size-checked list.
            async with CheckedSymbolsService(rsd) as service:
                await service.download(destination, force=False)
            from pymobiledevice3.safe_paths import resolve_device_path

            for item in files:
                path = resolve_device_path(destination, item.file_path.removeprefix("/"))
                if not path.is_file() or path.stat().st_size != item.file_size:
                    raise ValueError("incomplete_cache_download")
            summary["cacheDownloadComplete"] = True
        return summary


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return 0
    modes = {(): "list", ("--fetch-headers",): "headers", ("--fetch-cache",): "cache"}
    if tuple(sys.argv[1:]) not in modes:
        raise SystemExit("Usage: remote_symbols_probe.py [--self-test | --fetch-headers | --fetch-cache]")
    mode = modes[tuple(sys.argv[1:])]
    # Third-party diagnostic logs may include device identifiers or pairing material.
    logging.disable(logging.CRITICAL)
    stage = "phone_discovery"
    try:
        listing = subprocess.run([str(ROOT / "build/device_helper"), "list"],
                                 capture_output=True, text=True, timeout=15, check=True)
        phones = [d for d in json.loads(listing.stdout) if d.get("product") == "iPhone14,5"]
        if len(phones) != 1:
            print(json.dumps({"ok": False, "error": "single_target_phone_required"}))
            return 2
        stage = "remote_symbols"
        import pymobiledevice3.common as common

        (ROOT / ".tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="symbols-client-", dir=ROOT / ".tmp") as folder:
            # Pin-specific research setting: keep the library's temporary state local.
            common._HOMEFOLDER = Path(folder)
            result = asyncio.run(asyncio.wait_for(probe(phones[0]["udid"], mode),
                                                 timeout={"list": 40, "headers": 180, "cache": 900}[mode]))
        print(json.dumps({"ok": True, **result}))
        return 0
    except Exception as error:
        # Exception text can contain a UDID, address or raw service response.
        print(json.dumps({"ok": False, "stage": stage, "errorType": type(error).__name__}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
