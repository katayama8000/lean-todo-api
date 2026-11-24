import TodoApi.Domain

namespace TodoApi

structure Repository where
  list : IO (Array Todo)
  get : Nat → IO (Option Todo)
  insert : String → IO Todo
  replaceIfCompletionMatches : Todo → Bool → IO Bool
  delete : Nat → IO Bool

namespace Todos

def create (repo : Repository) (title : String) : IO (Except String Todo) :=
  match validateTitle title with
  | .error message => pure (.error message)
  | .ok title => .ok <$> repo.insert title

inductive ReplaceError where
  | invalidTitle (message : String)
  | notFound
  | alreadyCompleted
  | changed

def replace (repo : Repository) (id : Nat) (title : String) (completed : Bool) :
    IO (Except ReplaceError Todo) := do
  match validateTitle title with
  | .error message => return .error (.invalidTitle message)
  | .ok title =>
      let some current ← repo.get id | return .error .notFound
      unless current.canEdit do
        return .error .alreadyCompleted
      let updated := { current with title, completed }
      if ← repo.replaceIfCompletionMatches updated current.completed then
        return .ok updated
      return .error .changed

end Todos
end TodoApi
