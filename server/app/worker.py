"""Pool of Godot headless processes that run the shared game rules.

Each worker is `godot --headless --path <project> --script res://worker/worker.gd`
and speaks one JSON object per line on stdin/stdout. Calls are serialized per
worker; the pool hands out idle workers and restarts crashed or stuck ones.
"""
from __future__ import annotations

import asyncio
import itertools
import json
import logging

log = logging.getLogger("worker")

LINE_LIMIT = 64 * 1024 * 1024


class WorkerError(RuntimeError):
    pass


class Worker:
    def __init__(self, godot_bin: str, project_dir: str, timeout: float):
        self.godot_bin = godot_bin
        self.project_dir = project_dir
        self.timeout = timeout
        self.proc: asyncio.subprocess.Process | None = None

    async def start(self) -> None:
        self.proc = await asyncio.create_subprocess_exec(
            self.godot_bin, "--headless", "--path", self.project_dir, "--script", "res://worker/worker.gd",
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            limit=LINE_LIMIT,
        )
        hello = await asyncio.wait_for(self._read(), timeout=60)
        if not hello.get("ready"):
            raise WorkerError(f"worker did not start: {hello}")

    async def _read(self) -> dict:
        assert self.proc and self.proc.stdout
        while True:
            line = await self.proc.stdout.readline()
            if not line:
                raise WorkerError("worker exited")
            line = line.strip()
            if line.startswith(b"{"):  # skip the engine banner and warnings
                return json.loads(line)

    async def call(self, req: dict) -> dict:
        if self.proc is None or self.proc.returncode is not None:
            await self.start()
        assert self.proc and self.proc.stdin
        self.proc.stdin.write(json.dumps(req, ensure_ascii=False).encode() + b"\n")
        await self.proc.stdin.drain()
        return await asyncio.wait_for(self._read(), timeout=self.timeout)

    async def stop(self) -> None:
        if self.proc and self.proc.returncode is None:
            try:
                self.proc.stdin.close()
                await asyncio.wait_for(self.proc.wait(), timeout=5)
            except Exception:
                self.proc.kill()


class WorkerPool:
    def __init__(self, godot_bin: str, project_dir: str, size: int, timeout: float):
        self.workers = [Worker(godot_bin, project_dir, timeout) for _ in range(max(1, size))]
        self.idle: asyncio.Queue[Worker] = asyncio.Queue()
        self.ids = itertools.count(1)

    async def start(self) -> None:
        await asyncio.gather(*(w.start() for w in self.workers))
        for w in self.workers:
            self.idle.put_nowait(w)

    async def stop(self) -> None:
        await asyncio.gather(*(w.stop() for w in self.workers), return_exceptions=True)

    async def call(self, op: str, **kwargs) -> dict:
        req = {"id": next(self.ids), "op": op, **kwargs}
        w = await self.idle.get()
        try:
            res = await w.call(req)
        except (WorkerError, asyncio.TimeoutError, json.JSONDecodeError, BrokenPipeError, ConnectionResetError) as e:
            log.warning("worker failed (%s), restarting", e)
            if w.proc and w.proc.returncode is None:
                w.proc.kill()
            w.proc = None
            raise WorkerError(str(e)) from e
        finally:
            self.idle.put_nowait(w)
        if int(res.get("id") or 0) != req["id"]:
            raise WorkerError("worker answered out of order")
        return res
