{-# LANGUAGE OverloadedStrings #-}

-- | This module provides functions to execute a @GraphQL@ request.
module Language.GraphQL.Execute
    ( execute
    , executeWithName
    ) where

import qualified Data.Aeson as Aeson
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as Text
import Language.GraphQL.AST.Document
import qualified Language.GraphQL.AST.Core as AST.Core
import qualified Language.GraphQL.Execute.Transform as Transform
import Language.GraphQL.Error
import qualified Language.GraphQL.Schema as Schema

-- | The substitution is applied to the document, and the resolvers are applied
-- to the resulting fields.
--
-- Returns the result of the query against the schema wrapped in a /data/
-- field, or errors wrapped in an /errors/ field.
execute :: Monad m
    => NonEmpty (Schema.Resolver m) -- ^ Resolvers.
    -> Schema.Subs -- ^ Variable substitution function.
    -> Document -- @GraphQL@ document.
    -> m Aeson.Value
execute schema subs doc =
    maybe transformError (document schema Nothing) $ Transform.document subs doc
  where
    transformError = return $ singleError "Schema transformation error."

-- | The substitution is applied to the document, and the resolvers are applied
-- to the resulting fields. The operation name can be used if the document
-- defines multiple root operations.
--
-- Returns the result of the query against the schema wrapped in a /data/
-- field, or errors wrapped in an /errors/ field.
executeWithName :: Monad m
    => NonEmpty (Schema.Resolver m) -- ^ Resolvers
    -> Text -- ^ Operation name.
    -> Schema.Subs -- ^ Variable substitution function.
    -> Document -- ^ @GraphQL@ Document.
    -> m Aeson.Value
executeWithName schema name subs doc =
    maybe transformError (document schema $ Just name) $ Transform.document subs doc
  where
    transformError = return $ singleError "Schema transformation error."

document :: Monad m
    => NonEmpty (Schema.Resolver m)
    -> Maybe Text
    -> AST.Core.Document
    -> m Aeson.Value
document schema Nothing (op :| []) = operation schema op
document schema (Just name) operations = case NE.dropWhile matchingName operations of
    [] -> return $ singleError
        $ Text.unwords ["Operation", name, "couldn't be found in the document."]
    (op:_)  -> operation schema op
  where
    matchingName (AST.Core.Query (Just name') _) = name == name'
    matchingName (AST.Core.Mutation (Just name') _) = name == name'
    matchingName _ = False
document _ _ _ = return $ singleError "Missing operation name."

operation :: Monad m
    => NonEmpty (Schema.Resolver m)
    -> AST.Core.Operation
    -> m Aeson.Value
operation schema (AST.Core.Query _ flds)
    = runCollectErrs (Schema.resolve (toList schema) flds)
operation schema (AST.Core.Mutation _ flds)
    = runCollectErrs (Schema.resolve (toList schema) flds)
