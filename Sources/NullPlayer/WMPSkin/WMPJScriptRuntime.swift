import Foundation

enum WMPJScriptProtocol {
    static let version = 1
    static let maximumMutations = 4_096
    static let maximumHostCommands = 256
    static let maximumPreferenceCount = 512
    static let maximumRepaintHints = 4_096
    static let maximumTransactionsPerSecond = 120
}

enum WMPJScriptOperation: String, Codable { case createRealm, transaction, destroyRealm }

struct WMPJScriptExpression: Hashable, Codable, Sendable {
    let key: String
    let source: String
}

struct WMPJScriptRegistration: Hashable, Codable, Sendable {
    let id: String
    let properties: [String: WMPJSONValue]
}

struct WMPJScriptEvent: Hashable, Codable, Sendable {
    let name: String
    let targetID: String?
    let handlers: [String]
}

struct WMPJScriptBatch: Codable {
    let version: Int
    let operation: WMPJScriptOperation
    let registrations: [WMPJScriptRegistration]
    let scripts: [String]
    let expressions: [WMPJScriptExpression]
    let event: WMPJScriptEvent?
    let host: [String: WMPJSONValue]
    let preferences: [String: String]

    init(operation: WMPJScriptOperation = .transaction,
         registrations: [WMPJScriptRegistration] = [], scripts: [String] = [],
         expressions: [WMPJScriptExpression] = [], event: WMPJScriptEvent? = nil,
         host: [String: WMPJSONValue] = [:], preferences: [String: String] = [:]) {
        version = WMPJScriptProtocol.version
        self.operation = operation
        self.registrations = registrations
        self.scripts = scripts
        self.expressions = expressions
        self.event = event
        self.host = host
        self.preferences = preferences
    }
}

enum WMPJSONValue: Hashable, Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self), number.isFinite { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case let .bool(item): try value.encode(item)
        case let .number(item):
            guard item.isFinite else { throw EncodingError.invalidValue(item, .init(codingPath: encoder.codingPath, debugDescription: "non-finite number")) }
            try value.encode(item)
        case let .string(item): try value.encode(item)
        }
    }

    var number: Double? {
        switch self {
        case let .number(value): return value.isFinite ? value : nil
        case let .bool(value): return value ? 1 : 0
        case let .string(value): return Double(value).flatMap { $0.isFinite ? $0 : nil }
        case .null: return nil
        }
    }

    var string: String? {
        switch self {
        case let .string(value): return value
        case let .number(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return nil
        }
    }
}

struct WMPJScriptMutation: Hashable, Codable, Sendable {
    let targetID: String
    let property: String
    let value: WMPJSONValue
}

struct WMPJScriptHostCommand: Hashable, Codable, Sendable {
    let action: String
    let value: WMPJSONValue?
}

struct WMPJScriptPreferenceMutation: Hashable, Codable, Sendable {
    let key: String
    let value: String?
}

struct WMPJScriptTimerRequest: Hashable, Codable, Sendable {
    let token: Int
    let periodMilliseconds: Int
    let repeats: Bool
    let source: String
}

struct WMPJScriptDiagnostic: Hashable, Codable, Sendable {
    let code: String
    let message: String
}

struct WMPJScriptExpressionResult: Hashable, Codable {
    let key: String
    let value: WMPJSONValue?
    let dependencies: [String]
    let error: String?
}

struct WMPJScriptTransaction: Hashable, Codable {
    let version: Int
    let expressions: [WMPJScriptExpressionResult]
    let mutations: [WMPJScriptMutation]
    let hostCommands: [WMPJScriptHostCommand]
    let preferences: [WMPJScriptPreferenceMutation]
    let timers: [WMPJScriptTimerRequest]
    let diagnostics: [WMPJScriptDiagnostic]
    let repaintHints: [String]
}

/// Checked surface implemented by the compatibility bootstrap. Unsupported reads return a stable
/// default and one warning; members outside this table are never dynamically bridged to Swift.
enum WMPJScriptCompatibility {
    static let members: [String: Set<String>] = [
        "player": ["controls", "settings", "currentMedia", "currentPlaylist", "network", "playState", "status"],
        "controls": ["play", "pause", "stop", "previous", "next", "fastForward", "fastReverse", "currentPosition", "currentPositionString"],
        "settings": ["volume", "balance", "mute", "getMode", "setMode", "getString", "setString"],
        "media": ["name", "duration", "durationString", "getItemInfo"],
        "playlist": ["count", "item", "attributeCount", "getAttributeName"],
        "network": ["bufferingProgress", "receptionQuality", "bandWidth"],
        "eq": ["enabled", "gainLevel1", "gainLevel2", "gainLevel3", "gainLevel4", "gainLevel5", "gainLevel6", "gainLevel7", "gainLevel8", "gainLevel9", "gainLevel10"],
        "vis": ["currentEffect", "currentPreset"],
        "theme": ["currentViewID"],
        "view": ["left", "top", "width", "height"],
        "element": ["left", "top", "width", "height", "visible", "enabled", "value", "text", "down"],
        "popup": ["show"],
        "metadata": ["title", "artist", "album"]
    ]

    static func supports(object: String, member: String) -> Bool {
        members[object.lowercased()]?.contains(member) == true
    }
}

/// Production parent for a single killable helper batch. No skin code or expression executes in
/// this process. Each batch creates a fresh helper realm and carries only bounded JSON values.
final class WMPJScriptRuntime: @unchecked Sendable {
    let isolation: WMPScriptIsolation

    init(helperURL: URL, timeout: TimeInterval = 0.25) {
        isolation = WMPScriptIsolation(helperURL: helperURL, timeout: timeout, terminationGrace: 0.1)
    }

    func cancelAll() { isolation.cancelAll() }

    func transact(_ batch: WMPJScriptBatch) async -> Result<WMPJScriptTransaction, WMPPhase0Diagnostic> {
        await Task.detached(priority: .userInitiated) { [isolation] in
            guard batch.version == WMPJScriptProtocol.version else {
                return .failure(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil,
                    detail: "unsupported protocol version \(batch.version)"))
            }
            do {
                let script = try Self.program(for: batch)
                switch isolation.evaluate(script: script, callbackLimit: 0) {
                case let .failed(diagnostic): return .failure(diagnostic)
                case let .completed(response):
                    if let error = response.error {
                        return .failure(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil, detail: error))
                    }
                    guard let text = response.value, let data = text.data(using: .utf8),
                          data.count <= WMPPhase0Limits.scriptMessageBytes,
                          let transaction = try? JSONDecoder().decode(WMPJScriptTransaction.self, from: data),
                          transaction.version == WMPJScriptProtocol.version,
                          transaction.mutations.count <= WMPJScriptProtocol.maximumMutations,
                          transaction.hostCommands.count <= WMPJScriptProtocol.maximumHostCommands,
                          transaction.preferences.count <= WMPJScriptProtocol.maximumPreferenceCount,
                          transaction.timers.count <= WMPPhase0Limits.activeTimers,
                          transaction.repaintHints.count <= WMPJScriptProtocol.maximumRepaintHints else {
                        return .failure(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil,
                            detail: "invalid or unbounded transaction response"))
                    }
                    return .success(transaction)
                }
            } catch {
                return .failure(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil,
                    detail: error.localizedDescription))
            }
        }.value
    }

    private static func program(for batch: WMPJScriptBatch) throws -> String {
        let encoded = try JSONEncoder().encode(batch)
        guard encoded.count <= WMPPhase0Limits.scriptMessageBytes,
              let json = String(data: encoded, encoding: .utf8) else {
            throw WMPPhase0Diagnostic(code: .scriptMessageTooLarge, path: nil, detail: "batch exceeds 1 MiB")
        }
        return Self.bootstrap.replacingOccurrences(of: "__WMP_BATCH_JSON__", with: json)
    }

    private static let bootstrap = #"""
(function () {
  'use strict';
  var batch = __WMP_BATCH_JSON__;
  var out = {version:1, expressions:[], mutations:[], hostCommands:[], preferences:[], timers:[], diagnostics:[], repaintHints:[]};
  var reads = [];
  var timerToken = 0;
  function scalar(v) {
    if (v === null || typeof v === 'string' || typeof v === 'boolean') return v;
    if (typeof v === 'number' && isFinite(v)) return v;
    return String(v);
  }
  function warn(code, message) {
    if (out.diagnostics.length < 256) out.diagnostics.push({code:code, message:String(message)});
  }
  function command(action, value) {
    if (out.hostCommands.length < 256) out.hostCommands.push({action:action, value:value === undefined ? null : scalar(value)});
  }
  function element(id, initial) {
    var state = initial || {};
    return new Proxy(state, {
      get:function(target, property) {
        if (property === '__wmpID') return id;
        reads.push(id + '.' + String(property).toLowerCase());
        if (Object.prototype.hasOwnProperty.call(target, property)) return target[property];
        warn('unsupported-member', id + '.' + String(property)); return 0;
      },
      set:function(target, property, value) {
        value = scalar(value); target[property] = value;
        if (out.mutations.length < 4096) out.mutations.push({targetID:id, property:String(property), value:value});
        if (out.repaintHints.length < 4096) out.repaintHints.push(id);
        return true;
      }
    });
  }
  var elements = Object.create(null);
  batch.registrations.forEach(function(reg) {
    var proxy = element(reg.id, reg.properties);
    elements[reg.id] = proxy;
    if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(reg.id)) globalThis[reg.id] = proxy;
  });
  var host = batch.host || {};
  var view = elements.view || element('view', host.view || {}); globalThis.view = view;
  var controls = {
    play:function(){command('play');}, pause:function(){command('pause');}, stop:function(){command('stop');},
    previous:function(){command('previous');}, next:function(){command('next');},
    fastForward:function(){command('scanForward');}, fastReverse:function(){command('scanReverse');},
    get currentPosition(){reads.push('player.controls.currentposition'); return Number(host.currentTime || 0);},
    set currentPosition(v){command('seekSeconds', v);},
    get currentPositionString(){reads.push('player.controls.currentpositionstring'); return String(host.elapsedText || '0:00');}
  };
  var settings = {
    get volume(){reads.push('player.settings.volume'); return Number(host.volume || 0) * 100;},
    set volume(v){command('volumePercent', v);},
    get balance(){reads.push('player.settings.balance'); return Number(host.balance || 0) * 100;},
    set balance(v){command('balancePercent', v);},
    get mute(){reads.push('player.settings.mute'); return !!host.muted;},
    set mute(v){command('setMute', !!v);},
    getMode:function(name){reads.push('player.settings.' + String(name).toLowerCase()); return name === 'shuffle' ? !!host.shuffle : name === 'loop' ? !!host.repeatMode : false;},
    setMode:function(name,v){command(name === 'shuffle' ? 'setShuffle' : name === 'loop' ? 'setRepeat' : 'unsupported', !!v);},
    getString:function(key){reads.push('preferences.' + String(key)); return batch.preferences[String(key)] || '';},
    setString:function(key,value){out.preferences.push({key:String(key), value:String(value)});}
  };
  var media = {name:String(host.title || ''), duration:Number(host.duration || 0), durationString:String(host.durationText || '0:00'),
    getItemInfo:function(name){var key=String(name).toLowerCase(); return key === 'artist' ? String(host.artist||'') : key === 'album' ? String(host.album||'') : key === 'title' ? String(host.title||'') : '';}};
  var playlist = {count:Number(host.playlistCount || 0), item:function(){warn('unsupported-member','playlist.item'); return null;}, attributeCount:0, getAttributeName:function(){return '';}};
  var network = {bufferingProgress:Number(host.bufferingProgress || 0), receptionQuality:Number(host.receptionQuality || 0), bandWidth:0};
  var player = {controls:controls, settings:settings, currentMedia:media, currentPlaylist:playlist,
    network:network, playState:String(host.state || 'stopped'), status:String(host.status || '')};
  globalThis.player=player; globalThis.elements=elements; globalThis.network=network;
  globalThis.eq=element('eq',{}); globalThis.vis=element('vis',{}); globalThis.theme=element('theme',{currentViewID:String(host.viewID||'')});
  globalThis.ActiveXObject=undefined; globalThis.WScript=undefined; globalThis.Enumerator=undefined;
  globalThis.setTimeout=function(fn,ms){ if(out.timers.length>=256)return 0; var source=typeof fn==='function'?'('+fn.toString()+')()':String(fn); var token=++timerToken; out.timers.push({token:token,periodMilliseconds:Math.max(8,Math.floor(Number(ms)||0)),repeats:false,source:source}); return token; };
  globalThis.setInterval=function(fn,ms){var token=setTimeout(fn,ms); if(token)out.timers[out.timers.length-1].repeats=true; return token;};
  globalThis.clearTimeout=function(token){out.timers=out.timers.filter(function(t){return t.token!==token;});}; globalThis.clearInterval=globalThis.clearTimeout;
  function run(source, where) { try { (0,eval)(String(source)); } catch(e) { warn('script-error', where + ': ' + String(e)); } }
  batch.scripts.forEach(function(source,index){run(source,'script['+index+']');});
  batch.expressions.forEach(function(expr){
    reads=[]; var value=null,error=null;
    try { value=(0,eval)(String(expr.source)); value=scalar(value); if(typeof value==='number'&&!isFinite(value))throw new Error('non-finite result'); }
    catch(e){value=null;error=String(e);}
    if(error===null) { var dot=expr.key.lastIndexOf('.'); var target=expr.key.slice(0,dot), property=expr.key.slice(dot+1); if(elements[target]) elements[target][property]=value; }
    out.expressions.push({key:expr.key,value:value,dependencies:Array.from(new Set(reads)).sort(),error:error});
  });
  if(batch.event) batch.event.handlers.forEach(function(source,index){run(source,batch.event.name+'['+index+']');});
  if(out.preferences.length>512) out.preferences=out.preferences.slice(0,512);
  return JSON.stringify(out);
})()
"""#
}
