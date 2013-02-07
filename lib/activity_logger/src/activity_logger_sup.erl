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
% @private
-module(activity_logger_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

start_link(LogFile) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [LogFile]).

init([LogFile]) ->
    {ok, 
        {
            {one_for_one, 1, 60},
            [
                {
                    activity_logger_fd,
                    {activity_logger_fd, start_link, [LogFile]},
                    permanent,
                    2000,
                    worker,
                    [activity_logger_fd]
                }
            ]
        }
    }.
