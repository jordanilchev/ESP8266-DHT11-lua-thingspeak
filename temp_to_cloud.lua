-- ESP8266 model ESP-01 with DHT11 sensor
-- (with deepsleep cpu pin8 wired to RST)
-- pin:4 => GPIO1 on ESP-01
pin = 4
-- us to sec
SEC = 1000000
-- wifi
ap_name = "wifi-sid"
ap_pass = "wifi-password"
static_IP = {ip = "192.168.100.111", netmask = "255.255.255.0", gateway = "192.168.100.1" }
wifiMaxConnectTime = 10 -- sec
-- cloud reporting: http//api.thingspeak.com/update.json
thinkspeak_IP = "54.164.214.198"
thinkspeak_URL = "/update.json"
thinkspeak_API_key = '6ASQEC0H3D1FGEZP' 

function readSensor()
    local status, temp, humi, temp_dec, humi_dec = dht.read(pin)

    if status == dht.OK then
        print("DHT Temperature:"..temp.."; ".." Humidity:"..humi)
        return temp, humi
    elseif status == dht.ERROR_CHECKSUM then
        print( "DHT Checksum error." )
        return -1, -1
    elseif status == dht.ERROR_TIMEOUT then
        print( "DHT timed out." )
        return -1, -2
    end
end

function connectToWiFi(app_name, app_pass, sucessFunction, errorFunction)
    local counter = wifiMaxConnectTime*10;

    print("Setting up WIFI...")
    wifi.setmode(wifi.STATION)
    wifi.sta.config(app_name, app_pass)
    wifi.sta.setip(static_IP);
    wifi.sta.connect()

    print("Waiting for IP ")
    tmr.alarm(1, 100, 1, function() 
        --if wifi.sta.getip()== nil
        if wifi.sta.status() < 5 then
            counter = counter - 1
            --print(wifiMaxConnectTime*10-counter)
            if counter < 1 then
                tmr.stop(1)
                print("Failed to connect in "..wifiMaxConnectTime.." sec.")
                errorFunction("timed out after "..wifiMaxConnectTime.." sec.")
            end    
        else
            tmr.stop(1)
            print("Got IP: "..wifi.sta.getip().."["..(wifiMaxConnectTime*10-counter).." ticks]")
            sucessFunction()
            end 
        end)
end

function sendData(data, callback) -- { field1=xxx, filed2=yyy, ...}
    data["api_key"] = thinkspeak_API_key
    local json = cjson.encode(data)
    local content_lenght = string.len(json)

    print("Sending data")
    conn=net.createConnection(net.TCP, 0) 
    
    req = "POST "
        ..thinkspeak_URL                      
        .." HTTP/1.1\r\n" 
        .."Host: api.thingspeak.com\r\n"
        .."Connection: close\r\n"
        .."Accept: */*\r\n" 
        .."User-Agent: Mozilla/4.0 (compatible; esp8266 Lua; Windows NT 5.1)\r\n" 
        .."Content-Type: application/json\r\n"
        .."Content-Length: "..content_lenght.."\r\n"
        .."\r\n"
        ..json.."\r\n"

    conn:on("receive",
        function(conn, payload)
            print(payload)
        end)
    conn:on("sent",
        function(conn)
            print("Closing connection")
            conn:close()
            callback()
        end)
    conn:on("disconnection",
        function(conn)
            print("Got disconnection")
            callback()
        end)
        
    conn:connect(80,thinkspeak_IP)

    conn:on("connection", function(sck,c)
        conn:send(req)
    end)    
end

temp, humi = readSensor()
print("temp:"..temp)
vdd = adc.readvdd33()
print("vdd:"..vdd)

if temp >= 0 and temp <= 100 then
    connectToWiFi( ap_name, ap_pass,
        -- on sucesss
        function ()
            sendData({field1=temp,field2=humi, field3=vdd},
                function()
                    -- done
                    node.dsleep(600*SEC, 1)
                end)
        end,
        -- on error
        function (err)
            print(err)
            node.dsleep(30*60*SEC, 1)
        end)
else
    -- checksum failed, skip a beat
    print ("Deep sleep")
    node.dsleep(600*SEC, 1)
end
