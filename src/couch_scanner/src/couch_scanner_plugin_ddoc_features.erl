% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

% Scanner plugin to detect various design document features
%
% By default when enabled it will scan design documents for features slated to be
% deprecated in 4.0 such as: rewrites, lists, shows, updates. There are options
% to enable other feature checks: custom JS reducers, JS libraries, VDU functions,
% and JS filters.
%
% By default the scanning will start and run on the first node of the cluster only.
% It's possible to make the plugin run on all the and each node will pick a fraction
% of dbs to scan. That will make the scan go fast but might consume more resources. That options
% is contorlled via the run_on_first_node boolean setting.
%
% When features are detected they are aggregated per database and reported once all the
% design documents for a particular database have been processed. To get details about
% the specific design document enable the ddoc_report = true setting.
%

-module(couch_scanner_plugin_ddoc_features).
-behaviour(couch_scanner_plugin).

-export([
    start/2,
    resume/2,
    complete/1,
    checkpoint/1,
    db/2,
    ddoc/3
]).

-include_lib("couch_scanner/include/couch_scanner_plugin.hrl").

-record(st, {
    sid,
    dbname,
    report = #{},
    opts = #{},
    run_on_first_node = true,
    ddoc_report = false
}).

-define(UPDATES, <<"updates">>).
-define(SHOWS, <<"shows">>).
-define(LISTS, <<"lists">>).
-define(REWRITES, <<"rewrites">>).
-define(FILTERS, <<"filters">>).
-define(REDUCE, <<"reduce">>).
-define(VDU, <<"validate_doc_update">>).
-define(VIEWS, <<"views">>).

-define(OPTS, #{
    ?UPDATES => true,
    ?SHOWS => true,
    ?LISTS => true,
    ?REWRITES => true,
    ?FILTERS => false,
    ?REDUCE => false,
    ?VDU => false
}).

% Behavior callbacks

start(SId, #{}) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    St = init_config(#st{sid = SId}),
    case should_run(St) of
        true ->
            ?INFO("Starting.", [], #{sid => SId}),
            {ok, St};
        false ->
            ?INFO("Not starting. Not on first node.", [], #{sid => SId}),
            skip
    end.

resume(SId, #{<<"opts">> := OldOpts}) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    St = init_config(#st{sid = SId}),
    case {OldOpts == St#st.opts, should_run(St)} of
        {true, true} ->
            ?INFO("Resuming.", [], #{sid => SId}),
            {ok, St};
        {false, true} ->
            ?INFO("Resetting. Config changed.", [], #{sid => SId}),
            reset;
        {_, false} ->
            ?INFO("Not resuming. Not on first node.", [], #{sid => SId}),
            skip
    end.

complete(#st{sid = SId, dbname = DbName, report = Report} = St) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    report_per_db(St, DbName, Report),
    ?INFO("Completed", [], #{sid => SId}),
    {ok, #{}}.

checkpoint(#st{sid = SId, opts = Opts}) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    case Opts == opts() of
        true ->
            {ok, #{<<"opts">> => Opts}};
        false ->
            ?INFO("Resetting. Config changed.", [], #{sid => SId}),
            reset
    end.

db(#st{} = St, DbName) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    case St#st.run_on_first_node of
        true ->
            {ok, St};
        false ->
            % If we run on all nodes spread db checks across nodes
            case couch_scanner_util:consistent_hash_nodes(DbName) of
                true -> {ok, St};
                false -> {skip, St}
            end
    end.

ddoc(#st{} = St, _DbName, #doc{id = <<"_design/_", _/binary>>}) ->
    couch_log:error("~n ====================1 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    % These are auto-inserted ddocs _design/_auth, etc.
    {ok, St};
ddoc(#st{} = St, DbName, #doc{} = DDoc) ->
    couch_log:error("~n ====================2 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    #doc{body = {Props = [_ | _]}} = DDoc,
    case couch_util:get_value(<<"language">>, Props, <<"javascript">>) of
        <<"javascript">> -> {ok, check_ddoc(St, DbName, DDoc)};
        _ -> {ok, St}
    end.

% Private

init_config(#st{} = St) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    St#st{
        opts = opts(),
        run_on_first_node = cfg_bool("run_on_first_node", St#st.run_on_first_node),
        ddoc_report = cfg_bool("ddoc_report", St#st.ddoc_report)
    }.

should_run(#st{run_on_first_node = true}) ->
    couch_scanner_util:on_first_node();
should_run(#st{run_on_first_node = false}) ->
    true.

check_ddoc(#st{opts = Opts} = St, DbName, #doc{} = DDoc0) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    #doc{id = DDocId, body = Body} = DDoc0,
    DDoc = couch_scanner_util:ejson_map(Body),
    io:format("~n++++++ BEFORE St: ~p~n", [St]),
    {_Opts, Report} = maps:fold(fun check/3, {Opts, #{}}, DDoc),
    io:format("~n++++++ AFTER St: ~p~n", [St]),
    couch_log:error("~n++++++~n ~p:~p@~B~n Report:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, Report]),
    report(St, DbName, DDocId, Report).

check(?UPDATES, #{} = Obj, {#{?UPDATES := true} = Opts, Rep}) ->
    couch_log:error("~n ====================1 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?UPDATES, map_size(Obj), Rep)};
check(?REWRITES, <<_/binary>>, {#{?REWRITES := true} = Opts, Rep}) ->
    couch_log:error("~n ====================2 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?REWRITES, 1, Rep)};
check(?REWRITES, Arr, {#{?REWRITES := true} = Opts, Rep}) when is_list(Arr) ->
    couch_log:error("~n ====================3 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?REWRITES, length(Arr), Rep)};
check(?SHOWS, #{} = Obj, {#{?SHOWS := true} = Opts, Rep}) ->
    couch_log:error("~n ====================4 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?SHOWS, map_size(Obj), Rep)};
check(?LISTS, #{} = Obj, {#{?LISTS := true} = Opts, Rep}) ->
    couch_log:error("~n ====================5 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?LISTS, map_size(Obj), Rep)};
check(?FILTERS, #{} = Obj, {#{?FILTERS := true} = Opts, Rep}) ->
    couch_log:error("~n ====================6 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?FILTERS, map_size(Obj), Rep)};
check(?VDU, <<_/binary>>, {#{?VDU := true} = Opts, Rep}) ->
    couch_log:error("~n ====================7 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?VDU, 1, Rep)};
check(?VIEWS, #{} = Views, {#{?REDUCE := true} = Opts, Rep}) ->
    couch_log:error("~n ====================8 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {_, Rep1} = maps:fold(fun check_view/3, {Opts, Rep}, Views),
    {Opts, Rep1};
check(<<_/binary>>, _, {#{} = Opts, #{} = Rep}) ->
    couch_log:error("~n ====================9 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, Rep}.

check_view(_Name, #{?REDUCE := <<"_", _/binary>>}, {#{} = Opts, #{} = Rep}) ->
    couch_log:error("~n ====================1 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    % Built-in reducers
    {Opts, Rep};
check_view(_Name, #{?REDUCE := <<_/binary>>}, {#{} = Opts, #{} = Rep}) ->
    couch_log:error("~n ====================2 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, bump(?REDUCE, 1, Rep)};
check_view(_Name, _, {#{} = Opts, #{} = Rep}) ->
    couch_log:error("~n ====================3 ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Opts, Rep}.

bump(Field, N, #{} = Rep) ->
    maps:update_with(Field, fun(V) -> V + N end, N, Rep).

report(#st{} = St, _, _, #{} = Report) when map_size(Report) == 0 ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    St;
report(#st{} = St, DbName, DDocId, #{} = Report) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n++++++ DbName: ~p~n", [DbName]),
    io:format("~n++++++ DDocId: ~p~n", [DDocId]),
    io:format("~n++++++ Report: ~p~n", [Report]),
    #st{report = Total, dbname = PrevDbName} = St,
    io:format("~n++++++ Total: ~p~n", [Total]),
    io:format("~n++++++ PrevDbName: ~p~n", [PrevDbName]),
    report_per_ddoc(#st{} = St, DbName, DDocId, Report),
    case is_binary(PrevDbName) andalso DbName =/= PrevDbName of
        true ->
            % We switched dbs, so report stats for old db
            % and make the new one the current one
            report_per_db(St, PrevDbName, Total),
            St#st{report = Report, dbname = DbName};
        false ->
            % Keep accumulating per-db stats
            St#st{report = merge_report(Total, Report), dbname = DbName}
    end.

merge_report(#{} = Total, #{} = Update) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    Fun = fun(_K, V1, V2) -> V1 + V2 end,
    maps:merge_with(Fun, Total, Update).

report_per_db(#st{sid = SId}, DbName, #{} = Report) when
    map_size(Report) > 0, is_binary(DbName)
->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Fmt, Args} = report_fmt(Report),
    Meta = #{sid => SId, db => DbName},
    ?WARN(Fmt, Args, Meta);
report_per_db(#st{}, _, _) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    ok.

report_per_ddoc(#st{ddoc_report = false}, _DbName, _DDocId, _Report) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    ok;
report_per_ddoc(#st{ddoc_report = true, sid = SId}, DbName, DDocId, Report) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    {Fmt, Args} = report_fmt(Report),
    Meta = #{sid => SId, db => DbName, ddoc => DDocId},
    io:format("~n++++++ Meta: ~p~n", [Meta]),
    ?WARN(Fmt, Args, Meta).

report_fmt(Report) ->
    couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n++++++ Report: ~p~n", [Report]),
    Sorted = lists:sort(maps:to_list(Report)),
    io:format("~n++++++ Sorted: ~p~n", [Sorted]),
    FmtArgs = [{"~s:~p ", [K, V]} || {K, V} <- Sorted],
    io:format("~n++++++ FmtArgs: ~p~n", [FmtArgs]),
    {Fmt1, Args1} = lists:unzip(FmtArgs),
    io:format("~n++++++ {Fmt1, Args1}: ~p~n", [{Fmt1, Args1}]),
    Fmt2 = lists:flatten(Fmt1),
    io:format("~n++++++ Fmt2: ~p~n", [Fmt2]),
    Args2 = lists:flatten(Args1),
    io:format("~n++++++ Args2: ~p~n", [Args2]),
    {Fmt2, Args2}.

opts() ->
    Fun = fun(Key, Default) -> cfg_bool(binary_to_list(Key), Default) end,
    maps:map(Fun, ?OPTS).

cfg_bool(Key, Default) when is_list(Key), is_boolean(Default) ->
    config:get_boolean(atom_to_list(?MODULE), Key, Default).
