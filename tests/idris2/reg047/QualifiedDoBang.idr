import Data.Nat

namespace MaybeList
  public export
  (>>=) : (Maybe . List) a -> (a -> (Maybe . List) b) -> (Maybe . List) b
  (>>=) = (>>=) @{Compose}

  public export
  pure : a -> (Maybe . List) a
  pure = Just . (:: Nil)

  public export
  guard : Bool -> (Maybe . List) ()
  guard False = Nothing
  guard True = pure ()

namespace ListMaybe
  public export
  (>>=) : (List . Maybe) a -> (a -> (List . Maybe) b) -> (List . Maybe) b
  (>>=) = (>>=) @{Compose}

  public export
  (>>) : (List . Maybe) () -> Lazy ((List . Maybe) b) -> (List . Maybe) b
  (>>) = (>>) @{Compose}

  public export
  pure : a -> (List . Maybe) a
  pure = (:: Nil) . Just

  public export
  guard : Bool -> (List . Maybe) ()
  guard False = []
  guard True = ListMaybe.pure ()

-- Deliberately introduce ambiguity
namespace ListMaybe2
  public export
  (>>=) : (List . Maybe) a -> (a -> (List . Maybe) b) -> (List . Maybe) b
  (>>=) = (>>=) @{Compose}

-- "Qualified do" should propagate the namespace to nested bangs.
-- "pure" and "guard" calls generated by comprehensions are
-- also subject to "qualified do".
partial
propagateNSToBangs : (List . Maybe) (Nat, Nat)
propagateNSToBangs = ListMaybe.do
  let x = ![x | x <- map Just [1..10], modNat x 2 == 0]
  let f = !(map Just $ Prelude.do [(+ x) | x <- [1..3]])
  xs <- [MaybeList.do
    Just [!(Just $ Prelude.do [(*x) | x <- [1..10], modNat x 2 == 1])
          !(Just [4, 5, 6])]]
  y <- map Just xs
  [Just (f (10 * x), y)]