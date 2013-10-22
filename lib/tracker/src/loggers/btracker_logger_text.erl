% This file is part of "Enms" (http://sourceforge.net/projects/enms/)
% Copyright (C) 2012 <Sébastien Serre sserre.bx@gmail.com>
% 
% Enms is a Network Management System aimed to manage and monitor SNMP
% targets, monitor network hosts and services, provide a consistent
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
% The module implementing this behaviour is used by a tracker_target_channel
% to store values returned by the probes.
% @end
-module(btracker_logger_text).
-behaviour(beha_tracker_logger).
-include("../../include/tracker.hrl").

-export([
    init/2,
    log/2,
    dump/2
]).

init(_Conf, #probe_server_state{
        target          = Target,
        probe           = Probe,
        loggers_state   = LoggersState} = ProbeServerState) -> 

    TargetDir   = Target#target.directory,
    ProbeName   = Probe#probe.name,
    FileName    = io_lib:format("~s.txt", [ProbeName]),
    LogFile     = filename:absname_join(TargetDir, FileName),
    {ok, IoD} = file:open(LogFile, [append]),
    file:close(IoD),
    NewLoggersState =lists:keystore(?MODULE, 1, 
            LoggersState, {?MODULE, [{file_name, LogFile}] }),
    {ok, 
        ProbeServerState#probe_server_state{
            loggers_state = NewLoggersState
        }
    }.

log(#probe_server_state{loggers_state = LoggersState}, 
    #probe_return{original_reply = Msg, timestamp = T}) ->
    {?MODULE, Conf} = lists:keyfind(?MODULE, 1, LoggersState),
    {_, F}          = lists:keyfind(file_name, 1, Conf),
    EncodedMsg      = list_to_binary(io_lib:format("~p>>> ~s", [T, Msg])),
    file:write_file(F, EncodedMsg, [append]),
    ok.

dump(
        #target{id = TargetId, directory = Dir}, 
        #probe{id = ProbeId, name = Name, type = Type}) -> 
    % recreate file name
    FileName = io_lib:format("~s.txt", [Name]),
    LogFile  = filename:absname_join(Dir, FileName),
    {ok, B}  = file:read_file(LogFile),
    P = pdu('probeDump', {TargetId,ProbeId,Type,B}),
    {ok, [P]}.

pdu('probeDump', {TargetId, ProbeId, ProbeType, Binary}) ->
    {modTrackerPDU,
        {fromServer,
            {probeDump,
                {'ProbeDump',
                    atom_to_list(TargetId),
                    ProbeId,
                    ProbeType,
                    atom_to_list(?MODULE),
                    Binary}}}}.

