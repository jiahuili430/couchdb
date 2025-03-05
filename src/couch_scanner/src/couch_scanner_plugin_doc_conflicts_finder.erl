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

-module(couch_scanner_plugin_doc_conflicts_finder).
-behaviour(couch_scanner_plugin).

-export([
  start/2,
  resume/2,
%%  complete/1,
%%  checkpoint/1,
  db/2,
  doc_id/3
%%  ddoc/3
]).

-include_lib("couch_scanner/include/couch_scanner_plugin.hrl").

-record(st, {
  sid,
  opts = #{},
%%  dbname,
%%  report = #{},

  conflicts_cnt,
  deleted_conflicts_cnt,

  run_on_first_node = true
}).

-define(CONFLICTS, <<"conflicts">>).

-define(OPTS, #{
  ?CONFLICTS => true
}).

% Behavior callbacks

start(SId, #{}) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  couch_log:error("~n++++++~n ~p:~p@~B ~n SId:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, SId]),
  St = init_config(#st{sid = SId}),
  couch_log:error("~n++++++~n ~p:~p@~B ~n St:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, St]),
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
  couch_log:error("~n++++++~n ~p:~p@~B ~n SId:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, SId]),
  couch_log:error("~n++++++~n ~p:~p@~B ~n OldOpts:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, OldOpts]),
  St = init_config(#st{sid = SId}),
  couch_log:error("~n++++++~n ~p:~p@~B ~n St:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, St]),
  couch_log:error("~n++++++~n ~p:~p@~B ~n should_run(St):~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, should_run(St)]),
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

%%complete(#st{sid = SId, dbname = DbName, report = Report} = St) ->
%%  report_per_db(St, DbName, Report),
%%  ?INFO("Completed", [], #{sid => SId}),
%%  {ok, #{}}.

%%checkpoint(#st{sid = SId, opts = Opts}) ->
%%  case Opts == opts() of
%%    true ->
%%      {ok, #{<<"opts">> => Opts}};
%%    false ->
%%      ?INFO("Resetting. Config changed.", [], #{sid => SId}),
%%      reset
%%  end.

db(#st{} = St, DbName) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  couch_log:error("~n++++++~n ~p:~p@~B ~n St:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, St]),
  couch_log:error("~n++++++~n ~p:~p@~B ~n DbName:~p~n", [?MODULE, ?FUNCTION_NAME, ?LINE, DbName]),
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

doc_id(#st{} = St, <<?DESIGN_DOC_PREFIX, _/binary>>, _Db) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  io:format("~n++++++ design docs: {skip, St} ~n", []),
  {skip, St};
doc_id(#st{} = St, DocId, Db) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  io:format("~n++++++ docs: {ok, St} ~n", []),
  io:format("~n++++++ St: ~p~n", [St]),
  io:format("~n++++++ DocId: ~p~n", [DocId]),
  {ok, #doc_info{revs = Revs}} = couch_db:get_doc_info(Db, DocId),
  io:format("~n++++++ Revs: ~p~n", [Revs]),
  {DeletedConflicts, Conflicts} = lists:partition(fun(R) -> R#rev_info.deleted end, Revs),
  io:format("~n++++++ Conflicts: ~p~n", [Conflicts]),
  io:format("~n++++++ DeletedConflicts: ~p~n", [DeletedConflicts]),

%%  conflicts_cnt,
%%  deleted_conflicts_cnt,
%%  DeletedConflictsCnt = length(DeletedConflicts),
%%  ConflictsCnt = length(Conflicts) - 1,



%%  Conflicts:
%%  [{<<"d1">>,1}]
%%  DeletedConflicts:
%%  [{<<"d1">>,1}]


  {ok, St}.

%%doc_id(#st{} = St, <<?DESIGN_DOC_PREFIX, _/binary>>, _Db) ->
%%  {skip, St};
%%doc_id(#st{sid = SId, doc_cnt = C, max_docs = M} = St, _DocId, Db) when C > M ->
%%  Meta = #{sid => SId, db => Db},
%%  ?INFO("reached max docs ~p", [M], Meta),
%%  {stop, St};
%%doc_id(#st{doc_cnt = C, doc_step = S} = St, _DocId, _Db) when C rem S /= 0 ->
%%  {skip, St#st{doc_cnt = C + 1}};
%%doc_id(#st{doc_cnt = C} = St, _DocId, _Db) ->
%%  {ok, St#st{doc_cnt = C + 1}}.


%%ddoc(#st{} = St, _DbName, #doc{id = <<"_design/_", _/binary>>}) ->
%%  % These are auto-inserted ddocs _design/_auth, etc.
%%  {ok, St};
%%ddoc(#st{} = St, DbName, #doc{} = DDoc) ->
%%  #doc{body = {Props = [_ | _]}} = DDoc,
%%  case couch_util:get_value(<<"language">>, Props, <<"javascript">>) of
%%    <<"javascript">> -> {ok, check_ddoc(St, DbName, DDoc)};
%%    _ -> {ok, St}
%%  end.

% Private

init_config(#st{} = St) ->
  St#st{
    opts = opts(),
    run_on_first_node = cfg_bool("run_on_first_node", St#st.run_on_first_node)
  }.

should_run(#st{run_on_first_node = true}) ->
  couch_scanner_util:on_first_node();
should_run(#st{run_on_first_node = false}) ->
  true.

%%check_ddoc(#st{opts = Opts} = St, DbName, #doc{} = DDoc0) ->
%%  #doc{id = DDocId, body = Body} = DDoc0,
%%  DDoc = couch_scanner_util:ejson_map(Body),
%%  {_Opts, Report} = maps:fold(fun check/3, {Opts, #{}}, DDoc),
%%  report(St, DbName, DDocId, Report).
%%
%%check(?UPDATES, #{} = Obj, {#{?UPDATES := true} = Opts, Rep}) ->
%%  {Opts, bump(?UPDATES, map_size(Obj), Rep)};
%%check(?REWRITES, <<_/binary>>, {#{?REWRITES := true} = Opts, Rep}) ->
%%  {Opts, bump(?REWRITES, 1, Rep)};
%%check(?REWRITES, Arr, {#{?REWRITES := true} = Opts, Rep}) when is_list(Arr) ->
%%  {Opts, bump(?REWRITES, length(Arr), Rep)};
%%check(?SHOWS, #{} = Obj, {#{?SHOWS := true} = Opts, Rep}) ->
%%  {Opts, bump(?SHOWS, map_size(Obj), Rep)};
%%check(?LISTS, #{} = Obj, {#{?LISTS := true} = Opts, Rep}) ->
%%  {Opts, bump(?LISTS, map_size(Obj), Rep)};
%%check(?FILTERS, #{} = Obj, {#{?FILTERS := true} = Opts, Rep}) ->
%%  {Opts, bump(?FILTERS, map_size(Obj), Rep)};
%%check(?VDU, <<_/binary>>, {#{?VDU := true} = Opts, Rep}) ->
%%  {Opts, bump(?VDU, 1, Rep)};
%%check(?VIEWS, #{} = Views, {#{?REDUCE := true} = Opts, Rep}) ->
%%  {_, Rep1} = maps:fold(fun check_view/3, {Opts, Rep}, Views),
%%  {Opts, Rep1};
%%check(<<_/binary>>, _, {#{} = Opts, #{} = Rep}) ->
%%  {Opts, Rep}.
%%
%%check_view(_Name, #{?REDUCE := <<"_", _/binary>>}, {#{} = Opts, #{} = Rep}) ->
%%  % Built-in reducers
%%  {Opts, Rep};
%%check_view(_Name, #{?REDUCE := <<_/binary>>}, {#{} = Opts, #{} = Rep}) ->
%%  {Opts, bump(?REDUCE, 1, Rep)};
%%check_view(_Name, _, {#{} = Opts, #{} = Rep}) ->
%%  {Opts, Rep}.
%%
%%bump(Field, N, #{} = Rep) ->
%%  maps:update_with(Field, fun(V) -> V + N end, N, Rep).
%%
%%report(#st{} = St, _, _, #{} = Report) when map_size(Report) == 0 ->
%%  St;
%%report(#st{} = St, DbName, DDocId, #{} = Report) ->
%%  #st{report = Total, dbname = PrevDbName} = St,
%%  report_per_ddoc(#st{} = St, DbName, DDocId, Report),
%%  case is_binary(PrevDbName) andalso DbName =/= PrevDbName of
%%    true ->
%%      % We switched dbs, so report stats for old db
%%      % and make the new one the current one
%%      report_per_db(St, PrevDbName, Total),
%%      St#st{report = Report, dbname = DbName};
%%    false ->
%%      % Keep accumulating per-db stats
%%      St#st{report = merge_report(Total, Report), dbname = DbName}
%%  end.
%%
%%merge_report(#{} = Total, #{} = Update) ->
%%  Fun = fun(_K, V1, V2) -> V1 + V2 end,
%%  maps:merge_with(Fun, Total, Update).
%%
%%report_per_db(#st{sid = SId}, DbName, #{} = Report) when
%%  map_size(Report) > 0, is_binary(DbName)
%%  ->
%%  {Fmt, Args} = report_fmt(Report),
%%  Meta = #{sid => SId, db => DbName},
%%  ?WARN(Fmt, Args, Meta);
%%report_per_db(#st{}, _, _) ->
%%  ok.
%%
%%report_per_ddoc(#st{ddoc_report = false}, _DbName, _DDocId, _Report) ->
%%  ok;
%%report_per_ddoc(#st{ddoc_report = true, sid = SId}, DbName, DDocId, Report) ->
%%  {Fmt, Args} = report_fmt(Report),
%%  Meta = #{sid => SId, db => DbName, ddoc => DDocId},
%%  ?WARN(Fmt, Args, Meta).
%%
%%report_fmt(Report) ->
%%  Sorted = lists:sort(maps:to_list(Report)),
%%  FmtArgs = [{"~s:~p ", [K, V]} || {K, V} <- Sorted],
%%  {Fmt1, Args1} = lists:unzip(FmtArgs),
%%  Fmt2 = lists:flatten(Fmt1),
%%  Args2 = lists:flatten(Args1),
%%  {Fmt2, Args2}.

opts() ->
  Fun = fun(Key, Default) -> cfg_bool(binary_to_list(Key), Default) end,
  maps:map(Fun, ?OPTS).

cfg_bool(Key, Default) when is_list(Key), is_boolean(Default) ->
  config:get_boolean(atom_to_list(?MODULE), Key, Default).
