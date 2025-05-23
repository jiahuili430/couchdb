% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
% http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(mango_idx_text).

-export([
    validate_new/2,
    validate_fields/1,
    validate_index_def/1,
    add/2,
    remove/2,
    from_ddoc/1,
    to_json/1,
    columns/1,
    is_usable/3,
    get_default_field_options/1,
    indexable_fields/1
]).

-include_lib("couch/include/couch_db.hrl").
-include("mango.hrl").

validate_new(#idx{} = Idx, Db) ->
    {ok, Def} = do_validate(Idx#idx.def),
    maybe_reject_index_all_req(Def, Db),
    {ok, Idx#idx{def = Def}}.

validate_index_def(IndexInfo) ->
    do_validate(IndexInfo).

add(#doc{body = {Props0}} = DDoc, Idx) ->
    Texts1 =
        case proplists:get_value(<<"indexes">>, Props0) of
            {Texts0} -> Texts0;
            _ -> []
        end,
    NewText = make_text(Idx),
    Texts2 = lists:keystore(element(1, NewText), 1, Texts1, NewText),
    Props1 = lists:keystore(<<"indexes">>, 1, Props0, {<<"indexes">>, {Texts2}}),
    {ok, DDoc#doc{body = {Props1}}}.

remove(#doc{body = {Props0}} = DDoc, Idx) ->
    Texts1 =
        case proplists:get_value(<<"indexes">>, Props0) of
            {Texts0} ->
                Texts0;
            _ ->
                ?MANGO_ERROR({index_not_found, Idx#idx.name})
        end,
    Texts2 = lists:keydelete(Idx#idx.name, 1, Texts1),
    if
        Texts2 /= Texts1 -> ok;
        true -> ?MANGO_ERROR({index_not_found, Idx#idx.name})
    end,
    Props1 =
        case Texts2 of
            [] ->
                lists:keydelete(<<"indexes">>, 1, Props0);
            _ ->
                lists:keystore(<<"indexes">>, 1, Props0, {<<"indexes">>, {Texts2}})
        end,
    {ok, DDoc#doc{body = {Props1}}}.

from_ddoc({Props}) ->
    case lists:keyfind(<<"indexes">>, 1, Props) of
        {<<"indexes">>, {Texts}} when is_list(Texts) ->
            lists:flatmap(
                fun({Name, {VProps}}) ->
                    case validate_ddoc(VProps) of
                        invalid_ddoc ->
                            [];
                        Def ->
                            I = #idx{
                                type = <<"text">>,
                                name = Name,
                                def = Def
                            },
                            [I]
                    end
                end,
                Texts
            );
        _ ->
            []
    end.

to_json(Idx) ->
    {[
        {ddoc, Idx#idx.ddoc},
        {name, Idx#idx.name},
        {type, Idx#idx.type},
        {partitioned, Idx#idx.partitioned},
        {def, {def_to_json(Idx#idx.def)}}
    ]}.

columns(Idx) ->
    {Props} = Idx#idx.def,
    {<<"fields">>, Fields} = lists:keyfind(<<"fields">>, 1, Props),
    case Fields of
        <<"all_fields">> ->
            all_fields;
        _ ->
            {DFProps} = couch_util:get_value(<<"default_field">>, Props, {[]}),
            Enabled = couch_util:get_value(<<"enabled">>, DFProps, true),
            Default =
                case Enabled of
                    true -> [<<"$default">>];
                    false -> []
                end,
            Default ++
                lists:map(
                    fun({FProps}) ->
                        {_, Name} = lists:keyfind(<<"name">>, 1, FProps),
                        {_, Type} = lists:keyfind(<<"type">>, 1, FProps),
                        iolist_to_binary([Name, ":", Type])
                    end,
                    Fields
                )
    end.

% Mind that `is_usable/3` is not about "what fields can be answered by
% the index" but instead more along the lines of "this index will
% ensure that all the documents that should be returned for the query
% will be, because we checked that all the bits of the query that
% imply `$exists` for a field are used when we check that the indexing
% process will have included all the relevant documents in the index".
-spec is_usable(#idx{}, selector(), _) -> {boolean(), rejection_details()}.
is_usable(_, Selector, _) when Selector =:= {[]} ->
    {false, #{reason => [empty_selector]}};
is_usable(Idx, Selector, _) ->
    case columns(Idx) of
        all_fields ->
            {true, #{reason => []}};
        Cols ->
            Fields = indexable_fields(Selector),
            Usable = sets:is_subset(
                couch_util:set_from_list(Fields), couch_util:set_from_list(Cols)
            ),
            Reason = [field_mismatch || not Usable],
            Details = #{reason => Reason},
            {Usable, Details}
    end.

do_validate({Props}) ->
    {ok, Opts} = mango_opts:validate(Props, opts()),
    {ok, {Opts}};
do_validate(Else) ->
    ?MANGO_ERROR({invalid_index_text, Else}).

def_to_json({Props}) ->
    def_to_json(Props);
def_to_json([]) ->
    [];
def_to_json([{<<"fields">>, <<"all_fields">>} | Rest]) ->
    [{<<"fields">>, []} | def_to_json(Rest)];
def_to_json([{fields, Fields} | Rest]) ->
    [{<<"fields">>, fields_to_json(Fields)} | def_to_json(Rest)];
def_to_json([{<<"fields">>, Fields} | Rest]) ->
    [{<<"fields">>, fields_to_json(Fields)} | def_to_json(Rest)];
% Don't include partial_filter_selector in the json conversion
% if its the default value
def_to_json([{<<"partial_filter_selector">>, {[]}} | Rest]) ->
    def_to_json(Rest);
def_to_json([{Key, Value} | Rest]) ->
    [{Key, Value} | def_to_json(Rest)].

fields_to_json([]) ->
    [];
fields_to_json([{[{<<"name">>, Name}, {<<"type">>, Type0}]} | Rest]) ->
    ok = validate_field_name(Name),
    Type = validate_field_type(Type0),
    [{[{Name, Type}]} | fields_to_json(Rest)];
fields_to_json([{[{<<"type">>, Type0}, {<<"name">>, Name}]} | Rest]) ->
    ok = validate_field_name(Name),
    Type = validate_field_type(Type0),
    [{[{Name, Type}]} | fields_to_json(Rest)].

%% In the future, we can possibly add more restrictive validation.
%% For now, let's make sure the field name is not blank.
validate_field_name(<<"">>) ->
    throw(invalid_field_name);
validate_field_name(Else) when is_binary(Else) ->
    ok;
validate_field_name(_) ->
    throw(invalid_field_name).

validate_field_type(<<"string">>) ->
    <<"string">>;
validate_field_type(<<"number">>) ->
    <<"number">>;
validate_field_type(<<"boolean">>) ->
    <<"boolean">>.

validate_fields(<<"all_fields">>) ->
    {ok, all_fields};
validate_fields(Fields) ->
    try fields_to_json(Fields) of
        _ ->
            mango_fields:new(Fields)
    catch
        error:function_clause ->
            ?MANGO_ERROR({invalid_index_fields_definition, Fields});
        throw:invalid_field_name ->
            ?MANGO_ERROR({invalid_index_fields_definition, Fields})
    end.

validate_ddoc(VProps) ->
    try
        Def = proplists:get_value(<<"index">>, VProps),
        validate_index_def(Def),
        Def
    catch
        Error:Reason ->
            couch_log:error(
                "Invalid Index Def ~p: Error. ~p, Reason: ~p",
                [VProps, Error, Reason]
            ),
            invalid_ddoc
    end.

opts() ->
    [
        {<<"default_analyzer">>, [
            {tag, default_analyzer},
            {optional, true},
            {default, <<"keyword">>}
        ]},
        {<<"default_field">>, [
            {tag, default_field},
            {optional, true},
            {default, {[]}}
        ]},
        {<<"partial_filter_selector">>, [
            {tag, partial_filter_selector},
            {optional, true},
            {default, {[]}},
            {validator, fun mango_opts:validate_selector/1}
        ]},
        {<<"selector">>, [
            {tag, selector},
            {optional, true},
            {default, {[]}},
            {validator, fun mango_opts:validate_selector/1}
        ]},
        {<<"fields">>, [
            {tag, fields},
            {optional, true},
            {default, []},
            {validator, fun ?MODULE:validate_fields/1}
        ]},
        {<<"index_array_lengths">>, [
            {tag, index_array_lengths},
            {optional, true},
            {default, true},
            {validator, fun mango_opts:is_boolean/1}
        ]}
    ].

make_text(Idx) ->
    Text =
        {[
            {<<"index">>, Idx#idx.def},
            {<<"analyzer">>, construct_analyzer(Idx#idx.def)}
        ]},
    {Idx#idx.name, Text}.

get_default_field_options(Props) ->
    Default = couch_util:get_value(default_field, Props, {[]}),
    case Default of
        Bool when is_boolean(Bool) ->
            {Bool, <<"standard">>};
        {[]} ->
            {true, <<"standard">>};
        {Opts} ->
            Enabled = couch_util:get_value(<<"enabled">>, Opts, true),
            Analyzer = couch_util:get_value(
                <<"analyzer">>,
                Opts,
                <<"standard">>
            ),
            {Enabled, Analyzer}
    end.

construct_analyzer({Props}) ->
    DefaultAnalyzer = couch_util:get_value(
        default_analyzer,
        Props,
        <<"keyword">>
    ),
    {DefaultField, DefaultFieldAnalyzer} = get_default_field_options(Props),
    DefaultAnalyzerDef =
        case DefaultField of
            true ->
                [{<<"$default">>, DefaultFieldAnalyzer}];
            _ ->
                []
        end,
    case DefaultAnalyzerDef of
        [] ->
            <<"keyword">>;
        _ ->
            {[
                {<<"name">>, <<"perfield">>},
                {<<"default">>, DefaultAnalyzer},
                {<<"fields">>, {DefaultAnalyzerDef}}
            ]}
    end.

-spec indexable_fields(SelectorObject) -> Fields when
    SelectorObject :: any(),
    Fields :: [binary()].
indexable_fields({[]}) ->
    [];
indexable_fields(Selector) ->
    TupleTree = mango_selector_text:convert([], Selector),
    lists:uniq(indexable_fields([], TupleTree)).

-spec indexable_fields(Fields, abstract_text_selector()) -> Fields when
    Fields :: [binary()].
indexable_fields(Fields, {op_and, Args}) when is_list(Args) ->
    lists:foldl(
        fun(Arg, Fields0) -> indexable_fields(Fields0, Arg) end,
        Fields,
        Args
    );
%% For queries that use array element access or $in operations, two
%% fields get generated by mango_selector_text:convert. At index
%% definition time, only one field gets defined. In this situation, we
%% remove the extra generated field so that the index can be used. For
%% all other situations, we include the fields as normal.
indexable_fields(
    Fields,
    {op_or, [
        {op_field, Field0},
        {op_field, {[Name | _], _}} = Field1
    ]}
) ->
    case lists:member(<<"[]">>, Name) of
        true ->
            indexable_fields(Fields, {op_field, Field0});
        false ->
            Fields1 = indexable_fields(Fields, {op_field, Field0}),
            indexable_fields(Fields1, Field1)
    end;
indexable_fields(Fields, {op_or, Args}) when is_list(Args) ->
    lists:foldl(
        fun(Arg, Fields0) -> indexable_fields(Fields0, Arg) end,
        Fields,
        Args
    );
indexable_fields(Fields, {op_not, {ExistsQuery, Arg}}) when is_tuple(Arg) ->
    Fields0 = indexable_fields(Fields, ExistsQuery),
    indexable_fields(Fields0, Arg);
% forces "$exists" : false to use _all_docs
indexable_fields(_, {op_not, {_, false}}) ->
    [];
%% fieldname.[]:length is not a user defined field.
indexable_fields(Fields, {op_field, {[_, <<":length">>], _}}) ->
    Fields;
indexable_fields(Fields, {op_field, {Name, _}}) ->
    [iolist_to_binary(Name) | Fields];
%% In this particular case, the lucene index is doing a field_exists query
%% so it is looking at all sorts of combinations of field:* and field.*
%% We don't add the field because we cannot pre-determine what field will exist.
%% Hence we just return Fields and make it less restrictive.
indexable_fields(Fields, {op_fieldname, {_, _}}) ->
    Fields;
%% Similar idea to op_fieldname but with fieldname:null
indexable_fields(Fields, {op_null, {_, _}}) ->
    Fields;
%% Regular expression matching should be an exception to the rule
%% above because the type of the associated field is exact, it must be
%% a string.
indexable_fields(Fields, {op_regex, Name}) ->
    [iolist_to_binary([Name, ":string"]) | Fields];
indexable_fields(Fields, {op_default, _}) ->
    [<<"$default">> | Fields].

maybe_reject_index_all_req({Def}, Db) ->
    DbName = couch_db:name(Db),
    #user_ctx{name = User} = couch_db:get_user_ctx(Db),
    Fields = couch_util:get_value(fields, Def),
    case {Fields, forbid_index_all()} of
        {all_fields, "true"} ->
            ?MANGO_ERROR(index_all_disabled);
        {all_fields, "warn"} ->
            couch_log:warning(
                "User ~p is indexing all fields in db ~p",
                [User, DbName]
            );
        _ ->
            ok
    end.

forbid_index_all() ->
    config:get("mango", "index_all_disabled", "false").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

setup_all() ->
    Ctx = test_util:start_couch(),
    meck:expect(
        couch_log,
        warning,
        2,
        fun(_, _) ->
            throw({test_error, logged_warning})
        end
    ),
    Ctx.

teardown_all(Ctx) ->
    meck:unload(),
    test_util:stop_couch(Ctx).

setup() ->
    %default index all def that generates {fields, all_fields}
    Index = #idx{def = {[]}},
    DbName = <<"testdb">>,
    UserCtx = #user_ctx{name = <<"u1">>},
    {ok, Db} = couch_db:clustered_db(DbName, UserCtx),
    {Index, Db}.

teardown(_) ->
    ok.

index_all_test_() ->
    {
        setup,
        fun setup_all/0,
        fun teardown_all/1,
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun forbid_index_all/1,
                fun default_and_false_index_all/1,
                fun warn_index_all/1
            ]
        }
    }.

forbid_index_all({Idx, Db}) ->
    ?_test(begin
        ok = config:set("mango", "index_all_disabled", "true", false),
        ?assertThrow(
            {mango_error, ?MODULE, index_all_disabled},
            validate_new(Idx, Db)
        )
    end).

default_and_false_index_all({Idx, Db}) ->
    ?_test(begin
        config:delete("mango", "index_all_disabled", false),
        {ok, #idx{def = {Def}}} = validate_new(Idx, Db),
        Fields = couch_util:get_value(fields, Def),
        ?assertEqual(all_fields, Fields),
        ok = config:set("mango", "index_all_disabled", "false", false),
        {ok, #idx{def = {Def2}}} = validate_new(Idx, Db),
        Fields2 = couch_util:get_value(fields, Def2),
        ?assertEqual(all_fields, Fields2)
    end).

warn_index_all({Idx, Db}) ->
    ?_test(begin
        ok = config:set("mango", "index_all_disabled", "warn", false),
        ?assertThrow({test_error, logged_warning}, validate_new(Idx, Db))
    end).

indexable(Selector) ->
    indexable_fields(test_util:as_selector(Selector)).

indexable_fields_test() ->
    ?assertEqual(
        [<<"$default">>, <<"field1:boolean">>, <<"field2:number">>, <<"field3:string">>],
        indexable(
            #{
                <<"$default">> => #{<<"$text">> => <<"text">>},
                <<"field1">> => true,
                <<"field2">> => 42,
                <<"field3">> => #{<<"$regex">> => <<".*">>}
            }
        )
    ),
    ?assertEqual(
        [<<"f1:string">>, <<"f2:string">>, <<"f3:string">>, <<"f4:string">>, <<"f5:string">>],
        lists:sort(
            indexable(
                #{
                    <<"$and">> =>
                        [
                            #{<<"f1">> => <<"v1">>},
                            #{<<"f2">> => <<"v2">>}
                        ],
                    <<"$or">> =>
                        [
                            #{<<"f3">> => <<"v3">>},
                            #{<<"f4">> => <<"v4">>}
                        ],
                    <<"$not">> => #{<<"f5">> => <<"v5">>}
                }
            )
        )
    ),
    ?assertEqual(
        [<<"f2:string">>, <<"f3:string">>, <<"f1:string">>],
        indexable(
            #{
                <<"$and">> =>
                    [
                        #{<<"f2">> => <<"v1">>},
                        #{<<"f2">> => <<"v2">>}
                    ],
                <<"$not">> => #{<<"f3">> => <<"v5">>},
                <<"$or">> =>
                    [
                        #{<<"f1">> => <<"v3">>},
                        #{<<"f1">> => <<"v4">>}
                    ]
            }
        )
    ),
    ?assertEqual(
        [],
        indexable(
            #{
                <<"field1">> => null,
                <<"field2">> => #{<<"$size">> => 3},
                <<"field3">> => #{<<"$type">> => <<"type">>}
            }
        )
    ),
    ?assertEqual(
        [],
        indexable(
            #{
                <<"$and">> =>
                    [
                        #{<<"f1">> => null},
                        #{<<"f2">> => null}
                    ],
                <<"$or">> =>
                    [
                        #{<<"f3">> => null},
                        #{<<"f4">> => null}
                    ],
                <<"$not">> => #{<<"f5">> => null}
            }
        )
    ).

usable(Index, undefined, Fields) ->
    is_usable(Index, undefined, Fields);
usable(Index, Selector, Fields) ->
    is_usable(Index, test_util:as_selector(Selector), Fields).

is_usable_test() ->
    Usable = {true, #{reason => []}},
    EmptySelector = {false, #{reason => [empty_selector]}},
    FieldMismatch = {false, #{reason => [field_mismatch]}},
    ?assertEqual(EmptySelector, usable(undefined, #{}, undefined)),

    AllFieldsIndex = #idx{def = {[{<<"fields">>, <<"all_fields">>}]}},
    ?assertEqual(Usable, usable(AllFieldsIndex, undefined, undefined)),

    Field1 = {[{<<"name">>, <<"field1">>}, {<<"type">>, <<"string">>}]},
    Field2 = {[{<<"name">>, <<"field2">>}, {<<"type">>, <<"number">>}]},
    Index = #idx{def = {[{<<"fields">>, [Field1, Field2]}]}},
    ?assertEqual(Usable, usable(Index, #{<<"field1">> => <<"value">>}, undefined)),
    ?assertEqual(FieldMismatch, usable(Index, #{<<"field1">> => 42}, undefined)),
    ?assertEqual(FieldMismatch, usable(Index, #{<<"field3">> => true}, undefined)),
    ?assertEqual(
        Usable, usable(Index, #{<<"field1">> => #{<<"$type">> => <<"string">>}}, undefined)
    ),
    ?assertEqual(
        Usable, usable(Index, #{<<"field1">> => #{<<"$type">> => <<"boolean">>}}, undefined)
    ),
    ?assertEqual(
        Usable, usable(Index, #{<<"field3">> => #{<<"$type">> => <<"boolean">>}}, undefined)
    ),
    ?assertEqual(Usable, usable(Index, #{<<"field1">> => #{<<"$exists">> => true}}, undefined)),
    ?assertEqual(Usable, usable(Index, #{<<"field1">> => #{<<"$exists">> => false}}, undefined)),
    ?assertEqual(Usable, usable(Index, #{<<"field3">> => #{<<"$exists">> => true}}, undefined)),
    ?assertEqual(Usable, usable(Index, #{<<"field3">> => #{<<"$exists">> => false}}, undefined)),
    ?assertEqual(
        Usable,
        usable(Index, #{<<"field1">> => #{<<"$regex">> => <<".*">>}}, undefined)
    ),
    ?assertEqual(
        FieldMismatch,
        usable(Index, #{<<"field2">> => #{<<"$regex">> => <<".*">>}}, undefined)
    ),
    ?assertEqual(
        FieldMismatch,
        usable(Index, #{<<"field3">> => #{<<"$regex">> => <<".*">>}}, undefined)
    ),
    ?assertEqual(
        FieldMismatch,
        usable(Index, #{<<"field1">> => #{<<"$nin">> => [1, 2, 3]}}, undefined)
    ),
    ?assertEqual(
        Usable,
        usable(Index, #{<<"field2">> => #{<<"$nin">> => [1, 2, 3]}}, undefined)
    ),
    ?assertEqual(
        FieldMismatch,
        usable(Index, #{<<"field3">> => #{<<"$nin">> => [1, 2, 3]}}, undefined)
    ).
-endif.
