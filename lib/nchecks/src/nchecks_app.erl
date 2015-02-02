% @private
-module(nchecks_app).
-behaviour(application).

-export([
    start/2,
    stop/1
]).

start(_Type, _Args) ->
    nchecks_sup:start_link().

stop(_State) ->
    ok.
