/*
 * Sysmo NMS Network Management and Monitoring solution (http://www.sysmo.io)
 *
 * Copyright (c) 2012-2015 Sebastien Serre <ssbx@sysmo.io>
 *
 * This file is part of Sysmo NMS.
 *
 * Sysmo NMS is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Sysmo NMS is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Sysmo.  If not, see <http://www.gnu.org/licenses/>.
 */

package io.sysmo.nchecks;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.snmp4j.AbstractTarget;
import org.snmp4j.CommunityTarget;
import org.snmp4j.Snmp;
import org.snmp4j.UserTarget;
import org.snmp4j.mp.MPv3;
import org.snmp4j.mp.SnmpConstants;
import org.snmp4j.security.AuthMD5;
import org.snmp4j.security.AuthSHA;
import org.snmp4j.security.Priv3DES;
import org.snmp4j.security.PrivAES128;
import org.snmp4j.security.PrivAES192;
import org.snmp4j.security.PrivAES256;
import org.snmp4j.security.PrivDES;
import org.snmp4j.security.SecurityLevel;
import org.snmp4j.security.SecurityModel;
import org.snmp4j.security.SecurityModels;
import org.snmp4j.security.SecurityProtocols;
import org.snmp4j.security.USM;
import org.snmp4j.security.UsmUser;
import org.snmp4j.security.UsmUserEntry;
import org.snmp4j.smi.Address;
import org.snmp4j.smi.GenericAddress;
import org.snmp4j.smi.OID;
import org.snmp4j.smi.OctetString;
import org.snmp4j.transport.DefaultUdpTransportMapping;
import org.snmp4j.transport.UdpTransportMapping;
import org.snmp4j.security.nonstandard.PrivAES192With3DESKeyExtension;
import org.snmp4j.security.nonstandard.PrivAES256With3DESKeyExtension;

import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

// TODO handle snmp v3 usm user modification;
public class NChecksSNMP
{
    public Snmp snmp4jSession;
    private Map<String, AbstractTarget> agents;
    private static NChecksSNMP INSTANCE;
    private static Logger logger = LoggerFactory.getLogger(NChecksSNMP.class);

    public static void startSnmp(final String etcDir) throws Exception {
        new NChecksSNMP(etcDir);
    }
    private NChecksSNMP(final String etcDir) throws Exception
    {
        try {
            String eidFile = FileSystems
                    .getDefault()
                    .getPath(etcDir, "engine.id")
                    .toString();

            byte[] engineId = NChecksSNMP.getEngineId(eidFile);
            UdpTransportMapping transport = new DefaultUdpTransportMapping();
            snmp4jSession   = new Snmp(transport);
            USM usm         = new USM(SecurityProtocols.getInstance(),
                                                new OctetString(engineId), 0);
            SecurityModels.getInstance().addSecurityModel(usm);
            agents          = new HashMap<>();
            transport.listen();
        } catch (Exception e) {
            NChecksSNMP.logger.error("SNMP init fail: " + e.getMessage(), e);
            throw e;
        }
        INSTANCE = this;
    }

    public static NChecksSNMP getInstance() {return INSTANCE;}

    public Snmp getSnmpSession() {return snmp4jSession;}

    public synchronized void cleanup()
    {
        snmp4jSession.getUSM().removeAllUsers();
        agents = new HashMap<>();
    }

    public synchronized AbstractTarget getTarget(Query query) throws Exception
    {
        return getSnmpTarget(query);
    }

    private AbstractTarget getSnmpTarget(Query query) throws Exception
    {
        String targetId = query.get("target_id").asString();
        AbstractTarget target = agents.get(targetId);
        if (target != null) { return target; }

        target = generateTarget(query);
        if (target.getSecurityModel() != SecurityModel.SECURITY_MODEL_USM)
        {
            agents.put(targetId, target);
            return target;
        } else {
            UsmUser user     = generateUser(query);
            OctetString username = user.getSecurityName();
            UsmUserEntry oldUser =
                    snmp4jSession.getUSM().getUserTable().getUser(username);
            if (oldUser == null)
            {
                snmp4jSession.getUSM().addUser(user);
                agents.put(targetId, target);
                return target;
            }
            else
            {
                if (NChecksSNMP.usmUsersEquals(oldUser.getUsmUser(),user))
                {
                    // same users conf, ok
                    agents.put(targetId, target);
                    return target;
                }
                // TODO then replace old user with new one, use a thread lock
            }
        }
        throw new Exception("User name exists with differents credencials");
    }

    private AbstractTarget generateTarget(Query query) throws Exception, Error
    {
        String  host        = query.get("host").asString();
        int     port        = query.get("snmp_port").asInteger();
        String  secLevel    = query.get("snmp_seclevel").asString();
        String  version     = query.get("snmp_version").asString();
        int     retries     = query.get("snmp_retries").asInteger();
        int     timeout     = query.get("snmp_timeout").asInteger();
        
        Address address = GenericAddress.parse("udp:" + host + "/" + port);

        int secLevelConst = NChecksSNMP.getSecLevel(secLevel);

        switch (version)
        {
            case "3":
                String  secName = query.get("snmp_usm_user").asString();
                UserTarget targetV3 = new UserTarget();
                targetV3.setAddress(address);
                targetV3.setRetries(retries);
                targetV3.setTimeout(timeout);
                targetV3.setVersion(SnmpConstants.version3);
                targetV3.setSecurityLevel(secLevelConst);
                targetV3.setSecurityName(new OctetString(secName));
                return targetV3;

            default:
                String  community = query.get("snmp_community").asString();
                CommunityTarget target = new CommunityTarget();
                target.setCommunity(new OctetString(community));
                target.setAddress(address);
                target.setRetries(retries);
                target.setTimeout(timeout);
                if (version.equals("2c")) {
                    target.setVersion(SnmpConstants.version2c);
                } else {
                    target.setVersion(SnmpConstants.version1);
                }
                return target;
        }
    }

    private UsmUser generateUser(Query query) throws Exception, Error
    {

        OID authProtoOid =
                    NChecksSNMP.getAuthProto(query.get("snmp_authproto").asString());
        OID privProtoOid =
                    NChecksSNMP.getPrivProto(query.get("snmp_privproto").asString());

        OctetString uName =
                        new OctetString(query.get("snmp_usm_user").asString());
        OctetString authkey = 
                        new OctetString(query.get("snmp_authkey").asString());
        OctetString privkey = 
                        new OctetString(query.get("snmp_privkey").asString());

        return new UsmUser(uName,authProtoOid,authkey, privProtoOid,privkey);
    }


    // utilities functions
    private static char[] hexArray = "0123456789ABCDEF".toCharArray();

    // TODO test utf8 to byte might not work now
    public static byte[] getEngineId(String stringPath)
            throws Exception, Error
    {
        Path path = Paths.get(stringPath);
        if (Files.isRegularFile(path))
        {
            byte[] engineIdDump = Files.readAllBytes(path);
            String engineIdHex = new String(engineIdDump, "UTF-8");
            return NChecksSNMP.hexStringToBytes(engineIdHex); // return engine Id
        }
        else
        {
            byte[] engineId     = MPv3.createLocalEngineID();
            String engineIdHex  = NChecksSNMP.bytesToHexString(engineId);
            byte[] engineIdDump = engineIdHex.getBytes("UTF-8");
            Files.write(path, engineIdDump);
            return engineId;
        }
    }

    private static byte[] hexStringToBytes(String s)
    {
        int len = s.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(s.charAt(i), 16) << 4)
                    + Character.digit(s.charAt(i+1), 16));
        }
        return data;
    }

    private static String bytesToHexString(byte[] bytes) throws Exception,Error
    {
        char[] hexChars = new char[bytes.length * 2];
        for (int j=0; j<bytes.length; j++)
        {
            int v = bytes[j] & 0xFF;
            hexChars[j * 2] = hexArray[v >>> 4];
            hexChars[j * 2 + 1] = hexArray[v & 0x0F];
        }
        return new String(new String(hexChars).getBytes("UTF-8"), "UTF-8");
    }

    public static int getSecLevel(String constString) throws Exception
    {

        int seclevel;
        switch (constString)
        {
            case "authPriv":
                seclevel = SecurityLevel.AUTH_PRIV; break;
            case "authNoPriv":
                seclevel = SecurityLevel.AUTH_NOPRIV; break;
            case "noAuthNoPriv":
                seclevel = SecurityLevel.NOAUTH_NOPRIV; break;
            default:
                throw new Exception("No such seclevel!");
        }
        return seclevel;
    }

    public static OID getAuthProto(String constString) throws Exception
    {

        OID authProtoOid;
        switch (constString)
        {
            case "SHA": authProtoOid = AuthSHA.ID; break;
            case "MD5": authProtoOid = AuthMD5.ID; break;
            default:
                throw new Exception("unknown authentication protocol");
        }
        return authProtoOid;
    }

    public static OID getPrivProto(String constString) throws Exception
    {
        OID privProtoOid;
        switch (constString)
        {
            case "AES":         privProtoOid = PrivAES128.ID; break;
            case "AES192":      privProtoOid = PrivAES192.ID; break;
            case "AES256":      privProtoOid = PrivAES256.ID; break;
            case "DES":         privProtoOid = PrivDES.ID;    break;
            case "3DES":        privProtoOid = Priv3DES.ID;   break;
            case "AES192_3DES": privProtoOid = PrivAES192With3DESKeyExtension.ID; break;
            case "AES256_3DES": privProtoOid = PrivAES256With3DESKeyExtension.ID; break;
            default:
                throw new Exception("unknown private protocol");
        }

        return privProtoOid;
    }


    public static boolean usmUsersEquals(UsmUser a, UsmUser b)
    {
        return a.toString().equals(b.toString());
    }
}
