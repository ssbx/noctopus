% This file is part of "Enms" (http://sourceforge.net/projects/enms/)
% Copyright (C) 2012 <Sébastien Serre sserre.bx@gmail.com>
% 
% Enms is a Network Management System aimed to manage and monitor SNMP
% target, monitor network hosts and services, provide a consistent
% documentation system and tools to help network professionals
% to have a wide perspective of the networks they manage.
% 
% Enms is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% Enms is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with Enms.  If not, see <http://www.gnu.org/licenses/>.
% @doc
% launch/remove/add probes and switch messages. 
% <p>He is reponsible of
% <ul>
%   <li>switch probe messages (probe_evt) to the related modules depending 
%   on his type (activity, rrdmessages).</li>
%   <li>keep a clean state of target events for ifs when a client subscribe
%   to this channel</li>
%   <li> add, remove probes</li>
%   <li> keep his tracker_target_store record in sync</li>
% </ul>
% </p>
% @end
-module(tracker_target_channel).
-behaviour(gen_server).
-include("../include/tracker.hrl").

-export([
    init/1, 
    handle_call/3, 
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3]).

-export([
    start_link/2,
    launch_probes/1,
    subscribe/2,
    unsubscribe/1
]).

-record(chan_state, {
    chan_id,
    subscriber_count,
    target,
    rrd_dir,
    probes_store
}).

%%-------------------------------------------------------------
%% API
%%-------------------------------------------------------------
-spec start_link(string(), #target{}) -> 
        {ok, pid()} | ignore | {error, any()}.
% @doc
% Start the server.
% @end
start_link(RrdDir, #target{id = Id} = Target) ->
    gen_server:start_link({local, Id}, ?MODULE, [RrdDir, Target], []).


-spec launch_probes(target_id()) -> ok | {error, any()}.
% @doc
% Once the server running, call him to initialize his probes.
% @end
launch_probes(Id) ->
    gen_server:call(Id, launch_probes).

-spec subscribe(target_id(), any()) -> ok.
% @doc
% ifs module related.
% A client call. Will increase the subscriber_count by 1 and return only
% when all available information of the targets are sent.
% Once the #chan_state.subscriber_count > 0, every messages related to
% this target will be forwarded to ifs.
% @end
subscribe(TargetId, Client) ->
    gen_server:call(TargetId, {new_subscriber, Client}).

-spec unsubscribe(target_id()) -> ok.
% @doc
% ifs module related.
% Decrease the #chan_state.subscriber_count by 1. When the result = 0
% messages from this channel will not be forwarded to ifs.
% @end
unsubscribe(TargetId) ->
    gen_server:call(TargetId, {one_subscriber_less}).

%%-------------------------------------------------------------
%% GEN_SERVER CALLBACKS
%%-------------------------------------------------------------
% @doc
% Initiate the gen server.
% @end
init([RootRrdDir, #target{id = Id} = Target]) ->
    RrdTargetDir = filename:join(RootRrdDir, atom_to_list(Id)),
    ok = rrd_dir_exist(RrdTargetDir),
    gen_event:notify(tracker_events, {chan_init, Id}),
    {ok, 
        #chan_state{
            chan_id = Id,
            subscriber_count = 0,
            target = Target,
            rrd_dir = RrdTargetDir,
            probes_store = []
        }
    }.



% @doc
% Initialize the probes.
% @end
handle_call(launch_probes, _F, #chan_state{target = Target} = S) ->
    Probes = Target#target.probes,
    ProbesStore = lists:foldl(fun(Probe, Accum) ->
        {ok, Pid}   = tracker_probe_sup:new({Target, Probe, self()}),
        tracker_probe:launch(Pid),
        [{Pid, Probe, error} | Accum]
    end, [], Probes),
    {reply, ok, S#chan_state{probes_store = ProbesStore}};

handle_call(_R, _F, S) ->
    {noreply, S}.



% CAST
handle_cast({probe_evt, ProbePid, Msg}, 
        #chan_state{probes_store = ProbeStore} = S) ->
    {ProbePid, Probe, _Status} = lists:keyfind(ProbePid, 1, ProbeStore),
    probe_event(S, Probe, Msg),
    {noreply, S};

handle_cast(_R, S) ->
    {noreply, S}.



% OTHER
handle_info(_I, S) ->
    {noreply, S}.
terminate(_R, _S) ->
    normal.
code_change(_O, S, _E) ->
    {ok, S}.





%% PRIVATE FUNCTIONS
-spec rrd_dir_exist(string()) -> ok | {error, any()}.
rrd_dir_exist(RrdDir) ->
    case file:read_file_info(RrdDir) of
        {ok, _} ->
            ok;
        {error, enoent} ->
            file:make_dir(RrdDir);
        Other ->
            Other
    end.

-spec probe_event(#probe{}, #chan_state{}, any()) -> ok.
% @private
% probe event is an error message. We log.
probe_event(Chan, Probe, {Level = 'CRITICAL', Msg}) ->
    gen_event:notify(tracker_events, 
        {probe_event, status, {Level = Msg}, 
            {Chan#chan_state.chan_id, Probe#probe.id}}); 

probe_event(Chan, Probe, {Level = 'WARNING', Msg}) ->
    gen_event:notify(tracker_events, 
        {probe_event, status, {Level, Msg}, 
            {Chan#chan_state.chan_id, Probe#probe.id}}); 

probe_event(Chan, Probe, {Level = 'RECOVERY', Msg}) ->
    case Probe#probe.type of
        status ->
            gen_event:notify(tracker_events, 
                    {probe_event, status, {Level, Msg}, 
                        {Chan#chan_state.chan_id, Probe#probe.id}});
        fetch ->
            % rrdupdate
            gen_event:notify(tracker_events, 
                    {probe_event, status, {Level, Msg},
                        {Chan#chan_state.chan_id, Probe#probe.id}})
    end;

probe_event(Chan, Probe, {Level = 'OK', Msg}) ->
    case Probe#probe.type of
        status ->
            gen_event:notify(tracker_events, 
                    {probe_event, status, {Level, Msg}, 
                        {Chan#chan_state.chan_id, Probe#probe.id}});
        fetch ->
            % rrdupdate
            gen_event:notify(tracker_events, 
                    {probe_event, status, {Level, Msg},
                        {Chan#chan_state.chan_id, Probe#probe.id}})
    end;

probe_event(Chan, Probe, {Level = 'INFO', Msg}) ->
    gen_event:notify(tracker_events, 
        {probe_event, status, {Level, Msg}, 
            {Chan#chan_state.chan_id, Probe#probe.id}}); 

probe_event(_A,_B,C) ->
    io:format("Other ~p~n", [C]).
