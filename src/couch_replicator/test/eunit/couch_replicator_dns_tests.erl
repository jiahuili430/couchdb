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

-module(couch_replicator_dns_tests).

-include_lib("couch/include/couch_eunit.hrl").

match_pattern_test_() ->
    [
        ?_assert(couch_replicator_dns:match_pattern(
            "account.example.test", "*.example.test")),
        ?_assertNot(couch_replicator_dns:match_pattern(
            "example.test", "*.example.test")),
        ?_assert(couch_replicator_dns:match_pattern(
            "exact.example.test", "exact.example.test")),
        ?_assertNot(couch_replicator_dns:match_pattern(
            "other.example.test", "exact.example.test")),
        ?_assertNot(couch_replicator_dns:match_pattern(
            "short", "*.verylongpattern.example.test"))
    ].

parse_config_test_() ->
    [
        ?_assertEqual(
            2,
            length(couch_replicator_dns:parse_config(
                "*.example.test:proxy.internal, exact.example.test:127.0.0.1"
            ))
        ),
        ?_assertEqual([], couch_replicator_dns:parse_config(""))
    ].

resolve_host_test_() ->
    {setup,
     fun() ->
         meck:new(config, [passthrough]),
         meck:expect(config, get, fun
             ("replicator", "dns_overrides", _) ->
                 "*.example.test:egress.internal";
             (_, _, Default) ->
                 Default
         end)
     end,
     fun(_) ->
         meck:unload(config)
     end,
     [
         ?_assertEqual(
             {"egress.internal", "account.example.test"},
             couch_replicator_dns:resolve_host("account.example.test")
         ),
         ?_assertEqual(
             {"other.example.org", undefined},
             couch_replicator_dns:resolve_host("other.example.org")
         )
     ]}.
