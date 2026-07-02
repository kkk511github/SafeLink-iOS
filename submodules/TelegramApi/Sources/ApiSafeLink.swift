public extension Api.functions {
    enum safelink {
    }
}

public extension Api.functions.safelink {
    static func getGroupPrivateChatForbidden(channel: Api.InputChannel) -> (FunctionDescription, Buffer, DeserializeFunctionResponse<Api.Bool>) {
        let buffer = Buffer()
        buffer.appendInt32(0x06ebdea1)
        channel.serialize(buffer, true)
        return (FunctionDescription(name: "safelink.getGroupPrivateChatForbidden", parameters: [("channel", ConstructorParameterDescription(channel))]), buffer, DeserializeFunctionResponse { (buffer: Buffer) -> Api.Bool? in
            let reader = BufferReader(buffer)
            var result: Api.Bool?
            if let signature = reader.readInt32() {
                result = Api.parse(reader, signature: signature) as? Api.Bool
            }
            return result
        })
    }

    static func toggleGroupPrivateChatForbidden(channel: Api.InputChannel, enabled: Api.Bool) -> (FunctionDescription, Buffer, DeserializeFunctionResponse<Api.Updates>) {
        let buffer = Buffer()
        buffer.appendInt32(Int32(bitPattern: 0x94ba7b67))
        channel.serialize(buffer, true)
        enabled.serialize(buffer, true)
        return (FunctionDescription(name: "safelink.toggleGroupPrivateChatForbidden", parameters: [("channel", ConstructorParameterDescription(channel)), ("enabled", ConstructorParameterDescription(enabled))]), buffer, DeserializeFunctionResponse { (buffer: Buffer) -> Api.Updates? in
            let reader = BufferReader(buffer)
            var result: Api.Updates?
            if let signature = reader.readInt32() {
                result = Api.parse(reader, signature: signature) as? Api.Updates
            }
            return result
        })
    }
}
