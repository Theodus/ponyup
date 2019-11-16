use "collections"
use "crypto"
use "files"
use "http"

class QueryHandler is HTTPHandler
  let _notify: PonyupNotify
  let _cb: {(Payload val)} val

  new create(notify: PonyupNotify, cb: {(Payload val)} val) =>
    _notify = notify
    _cb = cb

  fun apply(res: Payload val) =>
    _cb(res)

  fun failed(
    reason: (AuthFailed val | ConnectionClosed val | ConnectFailed val))
  =>
    _notify.log(Err, "server unreachable, please try again later")

class DLHandler is HTTPHandler
  let _dl_dump: DLDump
  new create(dl_dump: DLDump) => _dl_dump = dl_dump
  fun apply(res: Payload val) => _dl_dump(res)
  fun chunk(bs: ByteSeq val) => _dl_dump.chunk(bs)
  fun finished() => _dl_dump.finished()

actor DLDump
  let _notify: PonyupNotify
  let _file_path: FilePath
  let _cb: {(String)} val
  let _file_name: String
  let _file: File
  let _digest: Digest = Digest.sha512()
  var _total: USize = 0
  var _progress: USize = 0
  var _percent: USize = 0

  new create(notify: PonyupNotify, file_path: FilePath, cb: {(String)} val) =>
    _notify = consume notify
    _file_path = consume file_path
    _cb = consume cb

    let components = _file_path.path.split("/")
    _file_name = try components(components.size() - 1)? else "" end
    _file = File(_file_path)

  be apply(res: Payload val) =>
    _total =
      try res.headers()("Content-Length")?.usize()? else 0 end

  be chunk(bs: ByteSeq val) =>
    _progress = _progress + bs.size()
    let percent = ((_progress.f64() / _total.f64()) * 100).usize()
    if percent > _percent then
      let progress_bar = recover String end
      progress_bar.append("\r  |")
      for i in Range(0, 100, 2) do
        progress_bar.append(if i <= percent then "█" else "-" end)
      end
      progress_bar .> append("| ") .> append(_file_name)
      _notify.write(consume progress_bar)
      _percent = percent
    end

    _file.write(bs)
    try _digest.append(bs)? end

  be finished() =>
    _notify.write("\n")
    _cb(ToHexString(_digest.final()))
