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
  complete/1,
  checkpoint/1,
  db/2,
  doc_id/3
]).

-include_lib("couch_scanner/include/couch_scanner_plugin.hrl").

-record(st, {
  sid,
  opts = #{},
  dbname,
  report = #{},
  run_on_first_node = true,
  doc_report = true
}).

-define(CONFLICTS, <<"conflicts">>).
-define(DELETED_CONFLICTS, <<"deleted_conflicts">>).
-define(REVS, <<"revs">>).

-define(OPTS, #{
  ?CONFLICTS => true,
  ?DELETED_CONFLICTS => true,
  ?REVS => true
}).

% Behavior callbacks

start(SId, #{}) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  io:format("~n++++++ start SId: ~p~n", [SId]),
  St = init_config(#st{sid = SId}),
  io:format("~n++++++ start St: ~p~n", [St]),
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
  io:format("~n++++++ resume SId: ~p~n", [SId]),
  io:format("~n++++++ resume OldOpts: ~p~n", [OldOpts]),
  St = init_config(#st{sid = SId}),
  io:format("~n++++++ resume St: ~p~n", [St]),
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
  io:format("~n++++++ complete SId: ~p~n", [SId]),
  io:format("~n++++++ complete DbName: ~p~n", [DbName]),
  io:format("~n++++++ complete Report: ~p~n", [Report]),
  io:format("~n++++++ complete St: ~p~n", [St]),
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
  io:format("~n++++++ db St: ~p~n", [St]),
  io:format("~n++++++ db DbName: ~p~n", [DbName]),
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
  io:format("~n++++++ doc_id docs: {ok, St} ~n", []),
  io:format("~n++++++ doc_id St: ~p~n", [St]),
  io:format("~n++++++ doc_id DocId: ~p~n", [DocId]),
  {ok, #doc_info{revs = Revs}} = couch_db:get_doc_info(Db, DocId),
  io:format("~n++++++ doc_id Revs: ~p~n", [Revs]),
  io:format("~n++++++ doc_id is_list(Revs): ~p~n", [is_list(Revs)]),
  io:format("~n++++++ doc_id length(Revs): ~p~n", [length(Revs)]),
  {ok, report(St, Db, DocId, Revs)}.

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

report(#st{} = St, _, _, Revs) when length(Revs) =< 1 ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  io:format("~n++++++ report Revs: ~p~n", [Revs]),
  io:format("~n++++++ report length(Revs): ~p~n", [length(Revs)]),
  St;
report(#st{opts = Opts} = St, Db, DocId, Revs) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  io:format("~n++++++ report Opts: ~p~n", [Opts]),
  io:format("~n++++++ report Db: ~p~n", [Db]),
  io:format("~n++++++ report DocId: ~p~n", [DocId]),
  io:format("~n++++++ report Revs: ~p~n", [Revs]),

  ShardsDbName = couch_db:name(Db),
  DbName = mem3:dbname(ShardsDbName),
  io:format("~n++++++ ShardsDbName: ~p~n", [ShardsDbName]),
  io:format("~n++++++ DbName: ~p~n", [DbName]),

  {DeletedConflicts, Conflicts} = lists:partition(fun(R) ->
    R#rev_info.deleted end, Revs),
  io:format("~n++++++ report Conflicts: ~p~n", [Conflicts]),
  io:format("~n++++++ report DeletedConflicts: ~p~n", [DeletedConflicts]),

  ConflictsCnt = length(Conflicts) - 1,
  DeletedConflictsCnt = length(DeletedConflicts),
  io:format("~n++++++ report ConflictsCnt: ~p~n", [ConflictsCnt]),
  io:format("~n++++++ report DeletedConflictsCnt: ~p~n", [DeletedConflictsCnt]),

  ConflictsReport =
    case maps:get(?CONFLICTS, Opts) of
      true -> #{?CONFLICTS => ConflictsCnt};
      false -> #{}
    end,
  DeletedConflictsReport =
    case maps:get(?DELETED_CONFLICTS, Opts) of
      true -> #{?DELETED_CONFLICTS => DeletedConflictsCnt};
      false -> #{}
    end,
  Report = maps:merge(ConflictsReport, DeletedConflictsReport),
  io:format("~n++++++ report ConflictsReport: ~p~n", [ConflictsReport]),
  io:format("~n++++++ report DeletedConflictsReport: ~p~n", [DeletedConflictsReport]),
  io:format("~n++++++ report Report: ~p~n", [Report]),

  #st{report = Total, dbname = PrevDbName} = St,
  io:format("~n++++++ report Total: ~p~n", [Total]),
  io:format("~n++++++ report PrevDbName: ~p~n", [PrevDbName]),

  DocReport =
    case maps:get(?REVS, Opts) of
      true ->
        ConflictsRevs =
          case maps:get(?CONFLICTS, Opts) of
            true ->
              #{?CONFLICTS => list_to_tuple([couch_doc:rev_to_str(R#rev_info.rev) || R <- Conflicts])};
            false -> #{}
          end,
        DeletedConflictsRevs =
          case maps:get(?DELETED_CONFLICTS, Opts) of
            true ->
              #{?DELETED_CONFLICTS => list_to_tuple([couch_doc:rev_to_str(R#rev_info.rev) || R <- DeletedConflicts])};
            false -> #{}
          end,
        maps:merge(ConflictsRevs, DeletedConflictsRevs);
      false -> Report
    end,
  report_per_doc(#st{} = St, DbName, DocId, DocReport),

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
  io:format("~n++++++ Args: ~p~n", [Args]),
  Meta = #{sid => SId, db => DbName},
  io:format("~n++++++ Meta: ~p~n", [Meta]),
  ?WARN(Fmt, Args, Meta);
report_per_db(#st{}, _, _) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  ok.

report_per_doc(#st{doc_report = false}, _DbName, _DocId, _Report) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  ok;
report_per_doc(#st{doc_report = true, sid = SId}, DbName, DocId, Report) ->
  couch_log:error("~n ==================== ~n ~p:~p@~B", [?MODULE, ?FUNCTION_NAME, ?LINE]),
  {Fmt, Args} = report_fmt(Report),
  Meta = #{sid => SId, db => DbName, doc => DocId},
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
