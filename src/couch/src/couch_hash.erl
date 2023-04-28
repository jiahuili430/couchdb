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

% This module is enable use of the built-in Erlang MD5 hashing function for
% non-cryptographic usage when in FIPS mode.
%
% For more details see:
%   https://www.erlang.org/doc/apps/crypto/fips.html#avoid-md5-for-hashing

-module(couch_hash).

-export([digest/1, digest_final/1, digest_init/0, digest_update/2]).

%% FIPS (
%  The ERLANG_MD5 define is set at compile time by --erlang-md5 configure flag
%  This is deprecated. Instead, FIPS mode is now detected automatically and the
%  build-in Erlang function will be used when FIPS mode is enabled.)
-ifdef(ERLANG_MD5).

digest(Data) ->
    erlang:md5(Data).

digest_final(Context) ->
    erlang:md5_final(Context).

digest_init() ->
    erlang:md5_init().

digest_update(Context, Data) ->
    erlang:md5_update(Context, Data).

-else.

digest(Data) ->
    case config:is_enabled(fips) of
        true -> erlang:md5(Data);
        false -> crypto:hash(md5, Data)
    end.

digest_final(Context) ->
    case config:is_enabled(fips) of
        true -> erlang:md5_final(Context);
        false -> crypto:hash_final(Context)
    end.

digest_init() ->
    case config:is_enabled(fips) of
        true -> erlang:md5_init();
        false -> crypto:hash_init(md5)
    end.

digest_update(Context, Data) ->
    case config:is_enabled(fips) of
        true -> erlang:md5_update(Context, Data);
        false -> crypto:hash_update(Context, Data)
    end.

-endif.
