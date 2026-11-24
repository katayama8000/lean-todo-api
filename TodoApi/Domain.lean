namespace TodoApi

structure Todo where
  id : Nat
  title : String
  completed : Bool
  deriving Repr, BEq

def Todo.canEdit (todo : Todo) : Bool :=
  !todo.completed

def validateTitle (input : String) : Except String String := do
  let title := input.trimAscii.toString
  if title.isEmpty || title.length > 200 then
    throw "Title must contain 1 to 200 characters."
  if title.contains (Char.ofNat 0) then
    throw "Title must not contain a null character."
  return title

end TodoApi
