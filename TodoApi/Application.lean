import TodoApi.Domain

namespace TodoApi

structure Repository where
  list : IO (Array Todo)
  get : Nat → IO (Option Todo)
  insert : String → IO Todo
  replace : Nat → String → Bool → IO (Option Todo)
  delete : Nat → IO Bool

namespace Todos

def create (repo : Repository) (title : String) : IO (Except String Todo) :=
  match validateTitle title with
  | .error message => pure (.error message)
  | .ok title => .ok <$> repo.insert title

def replace (repo : Repository) (id : Nat) (title : String) (completed : Bool) :
    IO (Except String (Option Todo)) :=
  match validateTitle title with
  | .error message => pure (.error message)
  | .ok title => .ok <$> repo.replace id title completed

end Todos
end TodoApi
