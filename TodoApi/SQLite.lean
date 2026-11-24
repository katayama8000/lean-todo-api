import Lean.Data.Json
import TodoApi.Application

open Lean

namespace TodoApi.SQLite

private def run (database : System.FilePath) (sql : String) : IO String := do
  let result ← IO.Process.output {
    cmd := "sqlite3"
    args := #["-batch", "-bail", "-json", "-cmd", ".timeout 5000", database.toString, sql]
  }
  unless result.exitCode == 0 do
    throw (IO.userError s!"SQLite exited with code {result.exitCode}: {result.stderr.trimAscii}")
  return result.stdout

private structure Row where
  id : Nat
  title : String
  completed : Nat
  deriving FromJson

private def rows (database : System.FilePath) (sql : String) : IO (Array Todo) := do
  let output ← run database sql
  if output.trimAscii.isEmpty then
    return #[]
  match Json.parse output >>= (fromJson? (α := Array Row)) with
  | .error message => throw (IO.userError s!"Invalid SQLite response: {message}")
  | .ok result => return result.map fun row =>
      { id := row.id, title := row.title, completed := row.completed == 1 }

-- Encode user text as a SQLite blob literal and cast it back to UTF-8 text.
private def textLiteral (value : String) : String := Id.run do
  let digits := "0123456789abcdef".toList.toArray
  let mut hex := ""
  for byte in value.toUTF8 do
    hex := hex.push digits[byte.toNat / 16]!
    hex := hex.push digits[byte.toNat % 16]!
  return s!"CAST(X'{hex}' AS TEXT)"

def openRepository (path : System.FilePath) : IO Repository := do
  let cwd ← IO.currentDir
  let database := if path.isAbsolute then path else cwd / path
  let _ ← run database "PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS todos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
      completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1))
    );"
  return {
    list := rows database "SELECT id, title, completed FROM todos ORDER BY id"
    get := fun id => do
      return (← rows database s!"SELECT id, title, completed FROM todos WHERE id = {id}")[0]?
    insert := fun title => do
      let inserted ← rows database s!"INSERT INTO todos (title) VALUES ({textLiteral title})
        RETURNING id, title, completed"
      match inserted[0]? with
      | some todo => return todo
      | none => throw (IO.userError "SQLite insert did not return a todo.")
    replaceIfCompletionMatches := fun todo expectedCompleted => do
      let flag := if todo.completed then 1 else 0
      let expectedFlag := if expectedCompleted then 1 else 0
      let updated ← rows database
        s!"UPDATE todos SET title = {textLiteral todo.title}, completed = {flag}
          WHERE id = {todo.id} AND completed = {expectedFlag} RETURNING id, title, completed"
      return !updated.isEmpty
    delete := fun id => do
      let deleted ← rows database s!"DELETE FROM todos WHERE id = {id} RETURNING id, title, completed"
      return !deleted.isEmpty
  }

end TodoApi.SQLite
