import Lean.Data.Json
import Std.Http
import TodoApi.Application

open Lean
open Std Http Server Async

namespace TodoApi

def maxBodyBytes : Nat := 16 * 1024

structure TodoHandler where
  repository : Repository

private structure CreateBody where
  title : String
  deriving FromJson

private structure ReplaceBody where
  title : String
  completed : Bool
  deriving FromJson

private def todoJson (todo : Todo) : Json :=
  Json.mkObj [
    ("id", toJson todo.id),
    ("title", toJson todo.title),
    ("completed", toJson todo.completed)
  ]

private def jsonResponse (status : Status) (payload : Json) :
    ContextAsync (Response Body.Any) := do
  Response.new |>.status status |>.json payload.compress

private def errorJson (message : String) : Json :=
  Json.mkObj [("error", toJson message)]

private def errorResponse (status : Status) (message : String) :
    ContextAsync (Response Body.Any) :=
  jsonResponse status (errorJson message)

private def methodNotAllowed (allow : String) : ContextAsync (Response Body.Any) := do
  Response.new |>.status .methodNotAllowed |>.header! "Allow" allow
    |>.json (errorJson "Method not allowed.").compress

private def readJson [FromJson α] (request : Request Body.Stream) : ContextAsync (Except String α) := do
  let bytes : ByteArray ← request.body.readAll (maximumSize := some maxBodyBytes.toUInt64)
  return match String.fromUTF8? bytes with
  | none => .error "Request body must be UTF-8."
  | some body =>
      match Json.parse body >>= fromJson? with
      | .ok value => .ok value
      | .error _ => .error "Request body does not match the expected JSON fields."

private def notFound : ContextAsync (Response Body.Any) :=
  errorResponse .notFound "Todo not found."

private def respondWithTodo : Option Todo → ContextAsync (Response Body.Any)
  | some todo => jsonResponse .ok (todoJson todo)
  | none => notFound

private def collection (repository : Repository) (request : Request Body.Stream) :
    ContextAsync (Response Body.Any) := do
  match request.line.method with
  | .get =>
      let todos ← repository.list
      jsonResponse .ok (.arr (todos.map todoJson))
  | .post =>
      match ← readJson (α := CreateBody) request with
      | .error message => errorResponse .badRequest message
      | .ok input =>
          match ← Todos.create repository input.title with
          | .error message => errorResponse .badRequest message
          | .ok todo =>
              Response.new |>.status .created |>.header! "Location" s!"/todos/{todo.id}"
                |>.json (todoJson todo).compress
  | _ => methodNotAllowed "GET, POST"

private def item (repository : Repository) (id : Nat) (request : Request Body.Stream) :
    ContextAsync (Response Body.Any) := do
  match request.line.method with
  | .get => respondWithTodo (← repository.get id)
  | .put =>
      match ← readJson (α := ReplaceBody) request with
      | .error message => errorResponse .badRequest message
      | .ok input =>
          match ← Todos.replace repository id input.title input.completed with
          | .error message => errorResponse .badRequest message
          | .ok todo => respondWithTodo todo
  | .delete =>
      if ← repository.delete id then
        Response.new |>.status .noContent |>.bytes ByteArray.empty
      else
        notFound
  | _ => methodNotAllowed "GET, PUT, DELETE"

private def dispatch (handler : TodoHandler) (request : Request Body.Stream) :
    ContextAsync (Response Body.Any) := do
  match (toString request.line.uri.path).splitOn "/" with
  | ["", "health"] =>
      if request.line.method == .get then
        jsonResponse .ok (Json.mkObj [("status", toJson "ok")])
      else
        methodNotAllowed "GET"
  | ["", "todos"] => collection handler.repository request
  | ["", "todos", rawId] =>
      if let some id := rawId.toNat? then
        if id > 0 && id <= 9223372036854775807 then
          return ← item handler.repository id request
      errorResponse .badRequest "Todo ID must be a positive 64-bit integer."
  | _ => errorResponse .notFound "Route not found."

instance : Handler TodoHandler where
  onRequest handler request := do
    try
      dispatch handler request
    catch error =>
      IO.eprintln s!"Request failed: {error}"
      errorResponse .internalServerError "Internal server error."

end TodoApi
