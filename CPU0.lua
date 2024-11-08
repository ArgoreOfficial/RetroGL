-- Retro Gadgets

local gl = require( "gl" )
local vc = gdt.VideoChip0

local img       = require("img.lua")
local img_top   = require("img_top.lua")
local img_front = require("img_front.lua")
local img_side  = require("img_side.lua")

-- helper function to copy pixeldata to a renderbuffer
function texImg2D( _buffer, _width, _height, _data:PixelData )
	vc:SetRenderBufferSize( _buffer, _width, _height )
	vc:RenderOnBuffer( _buffer )
	vc:BlitPixelData(vec2(0,0),_data)
	vc:RenderOnScreen()
end

-- try to keep polygons to a minimum
-- gl can only handle about 7000 quads before going under 30tps
local verticesCube = {
	-- sides
	{ vec3( 0.5,-0.5,-0.5), vec3( 0.5,-0.5, 0.5), vec3( 0.5, 0.5, 0.5), vec3( 0.5, 0.5,-0.5) }, -- +x
	{ vec3(-0.5,-0.5, 0.5), vec3(-0.5,-0.5,-0.5), vec3(-0.5, 0.5,-0.5), vec3(-0.5, 0.5, 0.5) }, -- -x
	-- top bottom
	{ vec3( 0.5, 0.5,-0.5), vec3( 0.5, 0.5, 0.5), vec3(-0.5, 0.5, 0.5), vec3(-0.5, 0.5,-0.5) }, -- +y
	{ vec3( 0.5,-0.5, 0.5), vec3( 0.5,-0.5,-0.5), vec3(-0.5,-0.5,-0.5), vec3(-0.5,-0.5, 0.5) }, -- -y
	-- front back
	{ vec3( 0.5,-0.5, 0.5), vec3(-0.5,-0.5, 0.5), vec3(-0.5, 0.5, 0.5), vec3( 0.5, 0.5, 0.5) }, -- +z
	{ vec3(-0.5,-0.5,-0.5), vec3( 0.5,-0.5,-0.5), vec3( 0.5, 0.5,-0.5), vec3(-0.5, 0.5,-0.5) }, -- -z
}

-- camera position and rotation
local viewPos = vec3(0,0,3)
local viewRot = vec3(0,0,0)

-- initialize gl 
gl.Load( gdt.VideoChip0 )

gl.SetParam( "GL_SORT", true )      -- sort triangles
gl.SetParam( "GL_CULL_FACE", true ) -- backface culling
gl.SetFOV( 90 )
gl.SetFarClip( 10.0 )
gl.SetViewTransform( viewPos, viewRot )

-- create vertex buffer objects
local vbQuad = gl.CreateVertexBuffer( verticesCube )

-- create texture buffer
texImg2D( 1, img_top.width,   img_top.height,   img_top:toPixelData() )
texImg2D( 2, img_front.width, img_front.height, img_front:toPixelData() )
texImg2D( 3, img_side.width,  img_side.height,  img_side:toPixelData() )
local texTop = vc.RenderBuffers[ 1 ]
local texFront = vc.RenderBuffers[ 2 ]
local texSides = vc.RenderBuffers[ 3 ]


function drawCube()
	gl.BindTexture( texSides )
	gl.DrawVerticesQuad( 1, 2 ) -- draw sides
	gl.BindTexture( texTop )
	gl.DrawVerticesQuad( 3, 2 ) -- draw top and bottom
	gl.BindTexture( texFront )
	gl.DrawVerticesQuad( 5, 2 ) -- draw front and back
end

function update()
	local t = gdt.CPU0.Time * 2 
		
	-- update view transform
	local r = math.cos( t * 0.6 )
	local dist = 3
	viewPos = vec3( 0, r + 0.3, dist )
	viewRot = vec3( r / dist, 0, 0 )
	gl.SetViewTransform( viewPos, viewRot )
	
	-- start drawing	
	gl.BeginFrame()
	gl.Clear()

	-- draw stationary cube
	gl.SetModelTransform( vec3( 0,0,0 ), vec3( 0.3,0.3,0 ) )
	drawCube()
	
	-- draw spinning cube
	gl.SetModelTransform( vec3( 1,0,0 ), vec3( t,t,t ) )
	drawCube()

	-- finalize frame and print debug info
	gl.EndFrame()
	gl.PrintDebugData()
end