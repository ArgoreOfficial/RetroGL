local gl = {}

------------------------------------------------------------
-- renderer state ------------------------------------------
------------------------------------------------------------

local mVC:VideoChip

local mVertexBufferCounter = 0
local mVertexBuffers = {}
local mVertexData = {}

local mHalfWidth = 1
local mHalfHeight = 1
local mFov = 45.0
local mAspect = 0   -- aspect ratio
local mNearClipDist = 0.1
local mNearFarQ = 0 -- near/far plane clamping

local mViewTranslation = vec3( 0, 0, 0 )
local mViewRotation    = vec3( 0, 0, 0 )
local mModelTranslation = vec3( 0, 0, 0 )
local mModelRotation    = vec3( 0, 0, 0 )

local mDrawTarget = -1
local mBoundTexture = nil
local mBoundTextureIsRenderBuffer = false
local mBoundRenderTarget : RenderBuffer = nil

local mDebugPrintOffset = 0

local mDrawQuads:{{}} = {}
local mDrawTriangles:{{}} = {}

local drawV0:vec3, drawV1:vec3, drawV2:vec3, drawV3:vec3
local drawLoopBegin:number, drawLoopEnd:number
local drawLoopSource:{{vec3}} = {}

local mParams = {
	["GL_SORT"] = false,
	["GL_CULL_FACE"] = false
}

------------------------------------------------------------
-- Maths ---------------------------------------------------
------------------------------------------------------------

function __v3RotateZ(_v:vec3, theta)
	if theta == 0 then return _v end
	return vec3(
			_v.X * math.cos(theta) - _v.Y * math.sin(theta),
			_v.X * math.sin(theta) + _v.Y * math.cos(theta),
			_v.Z 
	)
end

------------------------------------------------------------

function __v3RotateY(_v:vec3, theta)
	if theta == 0 then return _v end
	return vec3(
			_v.X *  math.cos(theta) + _v.Z * math.sin(theta),
			_v.Y,
			_v.X * -math.sin(theta) + _v.Z * math.cos(theta) 
	)
end

------------------------------------------------------------

function __v3RotateX(_v:vec3, theta)
	if theta == 0 then return _v end
	return vec3(
			_v.X,
			_v.Y * math.cos(theta) - _v.Z * math.sin(theta),
			_v.Y * math.sin(theta) + _v.Z * math.cos(theta))
end

------------------------------------------------------------

function __crossProduct( a, b ) : vec3
	return vec3(
		a.Y * (b.Z or 0) - (a.Z or 0) * b.Y, 
		(a.Z or 0) * b.X - a.X * (b.Z or 0), 
		a.X * b.Y - a.Y * b.X )
end

------------------------------------------------------------
-- Static Functions ----------------------------------------
------------------------------------------------------------

function __sortQuadFunction( _a, _b ) : boolean
	return _a[6] > _b[6]
end

------------------------------------------------------------

function __vec3ToScreen(_v:vec3, _near, _f, _a, _q)
	local _z = math.max(_v.Z, _near/2)
	
	return vec3(
		(_v.X * _f) / _z,
		(_v.Y * _f * _a) / _z,
		(_v.Z * _q) - (_near * _q)
	)
end

------------------------------------------------------------

function __project( _v:vec3 )
	_v = __v3RotateX(
			__v3RotateY(
					__v3RotateZ(_v, mModelRotation.Z)
					,mModelRotation.Y)
			,mModelRotation.X)
	_v += mModelTranslation * vec3(1,1,-1) 
	_v += mViewTranslation
	local a = __vec3ToScreen(_v, 0.1, mFov, mAspect, mNearFarQ )
	
	return vec3(
		(a.X + 1) * mHalfWidth, 
		(a.Y + 1) * mHalfHeight,
		-a.Z)
end

------------------------------------------------------------
-- API -----------------------------------------------------
------------------------------------------------------------

function gl.Load( _vc:VideoChip )
	mVC = _vc
	mHalfWidth = mVC.Width / 2
	mHalfHeight = mVC.Height / 2
end

------------------------------------------------------------

function gl.DebugPrint( ... )
	local font = gdt.ROM.System.SpriteSheets.StandardFont
	local str = string.format( ... )

	mVC:DrawText(vec2(0,mDebugPrintOffset), font, str, color.white, color.clear )
	mDebugPrintOffset += 8
end

------------------------------------------------------------

function gl.PrintDebugData()
	gl.DebugPrint( string.format( "FPS %i", 1 / gdt.CPU0.DeltaTime ) )
	gl.DebugPrint("")
	gl.DebugPrint( string.format( "Num Vertex Buffers: %i", mVertexBufferCounter ) )
	gl.DebugPrint( string.format( "Fov: %f", mFov ) ) 
	gl.DebugPrint( string.format( "Aspect: %f", mAspect ) )
	gl.DebugPrint( string.format( "Near Far Q: %f ", mNearFarQ ) )
	gl.DebugPrint("")
	gl.DebugPrint( "View Translation" )
	gl.DebugPrint( string.format( "  X: %f", mViewTranslation.X ) )
	gl.DebugPrint( string.format( "  Y: %f", mViewTranslation.Y ) )
	gl.DebugPrint( string.format( "  Z: %f", mViewTranslation.Z ) )
	gl.DebugPrint("")
	gl.DebugPrint( "View Rotation" )
	gl.DebugPrint( string.format( "  X: %f Radians", mViewRotation.X ) )
	gl.DebugPrint( string.format( "  Y: %f Radians", mViewRotation.Y ) )
	gl.DebugPrint( string.format( "  Z: %f Radians", mViewRotation.Z ) )
	gl.DebugPrint("")
	gl.DebugPrint( string.format( "Draw Target: %i", mDrawTarget ) )
	gl.DebugPrint( string.format( "Bound Texture: %s", mBoundTexture == nil and "none" or mBoundTexture.Type ) )
end

------------------------------------------------------------

function gl.SetParam( _param:string, _value )
	if mParams[ _param ] == nil then
		return
	end
	
	mParams[ _param ] = _value
end

------------------------------------------------------------

function gl.GetParam( _param:string )
	return mParams[ _param ]
end

------------------------------------------------------------

function gl.BeginFrame()
	mDebugPrintOffset = 0
	table.clear( mDrawQuads )
end

------------------------------------------------------------

function gl.EndFrame()
	gl.__DrawQuads()
end

------------------------------------------------------------

function gl.Clear()
	mVC:Clear( color.black )
end

------------------------------------------------------------

function gl.SetFOV( _degrees:number )
	mFov = 1 / math.tan(math.rad( _degrees ) / 2)
end

------------------------------------------------------------

function gl.SetFarClip( _far:number )
	mAspect   = mVC.Width / mVC.Height
	mNearFarQ = (mNearClipDist / (mNearClipDist - _far))
end

------------------------------------------------------------

function gl.SetViewTransform( _translation:vec3, _rotation:vec3 )
	mViewTranslation = _translation
	mViewRotation = _rotation
end

------------------------------------------------------------

function gl.SetModelTransform( _translation:vec3, _rotation:vec3 )
	mModelTranslation = _translation
	mModelRotation = _rotation
end

------------------------------------------------------------

function gl.CreateVertexBuffer( _data:{{vec3}} ) : {base:number, count:number}
	mVertexBufferCounter += 1
	mVertexBuffers[ mVertexBufferCounter ] = { base=#mVertexData+1, count=#_data }
	
	for i=1, #_data do
		mVertexData[ #mVertexData + 1 ] = _data[i]
	end
	
	return mVertexBuffers[ mVertexBufferCounter ]
end

------------------------------------------------------------

function gl.BindTexture( _texture )
	mBoundTexture = _texture
	mBoundTextureIsRenderBuffer = _texture.Type == "RenderBuffer"
end

------------------------------------------------------------

function gl.BindRenderBuffer( _buffer:number )
	if _buffer == 0 then
		mVC:RenderOnScreen()
	else
		mVC:RenderOnBuffer( _buffer )
	end
end

------------------------------------------------------------

function gl.DrawVerticesTri( _base:number, _count:number )
	local cullFace = mParams[ "GL_CULL_FACE" ]
	
	for i=_base, _base + _count - 1 do
		drawV0 = __project( mVertexData[i][1] )
		drawV1 = __project( mVertexData[i][2] )
		drawV2 = __project( mVertexData[i][3] )
		
		if cullFace and __crossProduct( drawV1 - drawV0, drawV2 - drawV0 ).Z > 0 then
				continue
		end
		
		mVC:DrawTriangle( 
				drawV0, 
				drawV1,
				drawV2,
				color.red
				)
	end
end

------------------------------------------------------------

function gl.DrawVerticesQuad( _base:number, _count:number )
	for i=_base, _base + _count - 1 do
		drawV0 = __project( mVertexData[i][1] )
		drawV1 = __project( mVertexData[i][2] )
		drawV2 = __project( mVertexData[i][3] )
		drawV3 = __project( mVertexData[i][4] )
		
		mDrawQuads[ #mDrawQuads + 1 ] = {
			drawV0, drawV1, drawV2, drawV3,           -- 1-4 vertices
			mBoundTexture,                            -- 5   texture
			drawV0.Z + drawV1.Z + drawV2.Z + drawV3.Z -- 6   Z val
		}
	end
end

function gl.__DrawQuads()
	local sort = mParams[ "GL_SORT" ]
	local cullFace = mParams[ "GL_CULL_FACE" ]
	
	if sort then
		table.sort( mDrawQuads, __sortQuadFunction )
	end
	
	for i=1,#mDrawQuads do
		drawV0 = mDrawQuads[i][1]
		drawV1 = mDrawQuads[i][2]
		drawV2 = mDrawQuads[i][3]
		drawV3 = mDrawQuads[i][4]
		gl.BindTexture( mDrawQuads[i][5] )

		if drawV0.Z < 0 and drawV1.Z < 0 and drawV2.Z < 0 and drawV3.Z < 0 then
			continue
		end
		
		if cullFace and __crossProduct( drawV1 - drawV0, drawV3 - drawV0 ).Z < 0 then
			continue
		end
		
		if mBoundTextureIsRenderBuffer then
			mVC:RasterRenderBuffer( drawV0, drawV1, drawV2, drawV3, mBoundTexture )
		else
			mVC:RasterSprite( drawV0, drawV1, drawV2, drawV3, mBoundTexture, 0, 0, color.white, color.clear )
		end
	end
end

------------------------------------------------------------

function gl.MultiDrawSprite( calls:{{}} ) 
  for i=1, #calls do
    mVC:DrawSprite( calls[i][1], calls[i][2], calls[i][3], calls[i][4], calls[i][5], calls[i][6] )
  end
end


-- :>
return gl