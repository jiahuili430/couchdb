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

-module(couch_replicator_dns).

-export([
    resolve_host/1,
    parse_config/1,
    match_pattern/2,
    get_overrides/0
]).

-type dns_override() :: {binary(), binary()}.

-spec resolve_host(string()) -> {string(), string() | undefined}.
resolve_host(Host) ->
    io:format("~n +++++++ Host:~p <- ~p:~p@~B", [Host, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n +++++++ unicode:characters_to_binary(Host):~p <- ~p:~p@~B", [unicode:characters_to_binary(Host), ?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n +++++++ get_overrides():~p <- ~p:~p@~B", [get_overrides(), ?MODULE, ?FUNCTION_NAME, ?LINE]),
    case find_override(unicode:characters_to_binary(Host), get_overrides()) of
        {ok, Target} ->
            io:format("~n +++++++ Target:~p <- ~p:~p@~B", [Target, ?MODULE, ?FUNCTION_NAME, ?LINE]),
            {binary_to_list(Target), Host};
        not_found ->
            {Host, undefined}
    end.

-spec get_overrides() -> [dns_override()].
get_overrides() ->
    case config:get("replicator", "dns_overrides", undefined) of
        undefined ->
            [];
        ConfigStr ->
            io:format("~n +++++++ ConfigStr:~p <- ~p:~p@~B", [ConfigStr, ?MODULE, ?FUNCTION_NAME, ?LINE]),
            parse_config(ConfigStr)
    end.

-spec parse_config(string()) -> [dns_override()].
parse_config(ConfigStr) ->
    Entries = binary:split(
        unicode:characters_to_binary(ConfigStr), <<",">>, [global, trim]
    ),
    io:format("~n +++++++ Entries:~p <- ~p:~p@~B", [Entries, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    lists:filtermap(fun parse_entry/1, Entries).

parse_entry(<<>>) ->
    false;
parse_entry(Entry0) ->
    Entry = string:trim(Entry0),
    io:format("~n +++++++ Entry:~p <- ~p:~p@~B", [Entry, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    case binary:split(Entry, <<":">>) of
        [Pattern0, Target0] ->
            Pattern = string:trim(Pattern0),
            Target = string:trim(Target0),
            case {Pattern, Target} of
                {<<>>, _} -> invalid_entry(Entry);
                {_, <<>>} -> invalid_entry(Entry);
                _ -> {true, {Pattern, Target}}
            end;
        _ ->
            invalid_entry(Entry)
    end.

invalid_entry(Entry) ->
    couch_log:warning("Invalid dns_override entry: ~ts", [Entry]),
    false.

find_override(_Host, []) ->
    not_found;
find_override(Host, [{Pattern, Target} | Rest]) ->
    case match_pattern(Host, Pattern) of
        true ->
            {ok, Target};
        false ->
            find_override(Host, Rest)
    end.

-spec match_pattern(binary() | string(), binary() | string()) -> boolean().
match_pattern(Host0, Pattern0) ->
    io:format("~n +++++++ Host0:~p <- ~p:~p@~B", [Host0, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    Host = unicode:characters_to_binary(Host0),
    io:format("~n +++++++ Host:~p <- ~p:~p@~B", [Host, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n +++++++ Pattern0:~p <- ~p:~p@~B", [Pattern0, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    Pattern = unicode:characters_to_binary(Pattern0),
    io:format("~n +++++++ Pattern:~p <- ~p:~p@~B", [Pattern, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    match_pattern_binary(Host, Pattern).

match_pattern_binary(Host, <<"*", Suffix/binary>>) ->
    % wildcard match: extract last N bytes from Host and compare to Suffix
    % size check prevents binary:part crash when Host is shorter than Suffix
    io:format("~n +++++++ Host:~p <- ~p:~p@~B", [Host, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n +++++++ Suffix:~p <- ~p:~p@~B", [Suffix, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    HostSize = byte_size(Host),
    SuffixSize = byte_size(Suffix),
    io:format("~n +++++++ HostSize:~p <- ~p:~p@~B", [HostSize, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n +++++++ SuffixSize:~p <- ~p:~p@~B", [SuffixSize, ?MODULE, ?FUNCTION_NAME, ?LINE]),

    io:format("~n +++++++ HostSize - SuffixSize:~p <- ~p:~p@~B", [HostSize - SuffixSize, ?MODULE, ?FUNCTION_NAME, ?LINE]),

    io:format("~n +++++++ binary:part(Host, HostSize - SuffixSize, SuffixSize):~p <- ~p:~p@~B", [binary:part(Host, HostSize - SuffixSize, SuffixSize), ?MODULE, ?FUNCTION_NAME, ?LINE]),
    HostSize >= SuffixSize andalso
        binary:part(Host, HostSize - SuffixSize, SuffixSize) =:= Suffix;
match_pattern_binary(Host, Pattern) ->
    io:format("~n +++++++ Host:~p <- ~p:~p@~B", [Host, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    io:format("~n +++++++ Pattern:~p <- ~p:~p@~B", [Pattern, ?MODULE, ?FUNCTION_NAME, ?LINE]),
    Host =:= Pattern.
