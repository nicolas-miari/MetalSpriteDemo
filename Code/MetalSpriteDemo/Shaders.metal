//
//  Shaders.metal
//  MetalSpriteDemo
//
//  Created by Nicolás Miari on 2019/04/10.
//  Copyright © 2019 Nicolás Miari. All rights reserved.
//

    #include <metal_stdlib>
    using namespace metal;

    struct Constants {
        float4x4 modelViewProjection;
    };

    struct VertexIn {
        float4 position  [[ attribute(0) ]];
        float2 texCoords [[ attribute(1) ]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoords;
    };

    vertex VertexOut sprite_vertex_transform(device VertexIn *vertices [[buffer(0)]],
                                             constant Constants &uniforms [[buffer(1)]],
                                             uint vertexId [[vertex_id]]) {

        float4 modelPosition = vertices[vertexId].position;
        VertexOut out;

        out.position = uniforms.modelViewProjection * modelPosition;
        out.texCoords = vertices[vertexId].texCoords;

        return out;
    }

    fragment float4 sprite_fragment_textured(VertexOut fragmentIn [[stage_in]],
                                             texture2d<float, access::sample> tex2d [[texture(0)]],
                                             constant Constants &uniforms [[buffer(1)]],
                                             sampler sampler2d [[sampler(0)]]) {

        float4 surfaceColor = tex2d.sample(sampler2d, fragmentIn.texCoords);

        return surfaceColor;
    }
