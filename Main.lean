import TodoApi.Http
import TodoApi.SQLite

open Std Async Http TodoApi

def main : IO Unit := do
  let bind := (← IO.getEnv "TODO_BIND").getD "127.0.0.1"
  let host ← match bind with
    | "127.0.0.1" => pure (Net.IPv4Addr.ofParts 127 0 0 1)
    | "0.0.0.0" => pure (Net.IPv4Addr.ofParts 0 0 0 0)
    | _ => throw (IO.userError "TODO_BIND must be 127.0.0.1 or 0.0.0.0.")
  let rawPort := (← IO.getEnv "TODO_PORT").getD "8080"
  let some port := rawPort.toNat? | throw (IO.userError "TODO_PORT must be an integer.")
  unless port > 0 && port <= 65535 do
    throw (IO.userError "TODO_PORT must be between 1 and 65535.")
  let database := (← IO.getEnv "TODO_DB").getD "todos.sqlite3"
  if database.isEmpty || database == ":memory:" then
    throw (IO.userError "TODO_DB must name a SQLite file.")
  let repository ← SQLite.openRepository ⟨database⟩
  Async.block do
    let address : Net.SocketAddress := .v4 ⟨host, port.toUInt16⟩
    let server ← Server.serve address (TodoHandler.mk repository) { maxBodySize := maxBodyBytes }
    IO.println s!"Listening on http://{bind}:{port}"
    server.waitShutdown
