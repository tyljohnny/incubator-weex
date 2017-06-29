/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * 
 *   http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import "WXComponent+Layout.h"
#import "WXComponent_internal.h"
#import "WXTransform.h"
#import "WXAssert.h"
#import "WXComponent_internal.h"
#import "WXSDKInstance_private.h"
#import "WXComponent+BoxShadow.h"

@implementation WXComponent (Layout)

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

#pragma mark Public

- (void)setNeedsLayout
{
    _isLayoutDirty = YES;
    WXComponent *supercomponent = [self supercomponent];
    if(supercomponent){
        [supercomponent setNeedsLayout];
    }
}

- (BOOL)needsLayout
{
    return _isLayoutDirty;
}

- (CGSize (^)(CGSize))measureBlock
{
    return nil;
}

- (void)layoutDidFinish
{
    WXAssertMainThread();
}

#pragma mark Private

- (void)_initCSSNodeWithStyles:(NSDictionary *)styles
{
    _cssNode = YGNodeNew();
    
    YGNodeSetPrintFunc(_cssNode, cssNodePrint);
//    _cssNode->get_child = cssNodeGetChild;
//    _cssNode->is_dirty = cssNodeIsDirty;
    if ([self measureBlock]) {
        YGNodeSetMeasureFunc(_cssNode, cssNodeMeasure);
    }
    YGNodeSetContext(_cssNode, (__bridge void *)self);
    
    [self _recomputeCSSNodeChildren];
    [self _fillCSSNode:styles];
    
    // To be in conformity with Android/Web, hopefully remove this in the future.
    if ([self.ref isEqualToString:WX_SDK_ROOT_REF]) {
        if (YGFloatIsUndefined(YGNodeStyleGetHeight(_cssNode).value) && self.weexInstance.frame.size.height) {
            YGNodeStyleSetHeight(_cssNode, self.weexInstance.frame.size.height);
        }
        
        if (YGFloatIsUndefined(YGNodeStyleGetWidth(_cssNode).value) && self.weexInstance.frame.size.width) {
            YGNodeStyleSetWidth(_cssNode, self.weexInstance.frame.size.width);
        }
    }
}

- (void)_updateCSSNodeStyles:(NSDictionary *)styles
{
    [self _fillCSSNode:styles];
}

-(void)_resetCSSNodeStyles:(NSArray *)styles
{
    [self _resetCSSNode:styles];
}

- (void)_recomputeCSSNodeChildren
{
//    _cssNode->children_count = (int)[self _childrenCountForLayout];
}

- (NSUInteger)_childrenCountForLayout
{
    NSArray *subcomponents = _subcomponents;
    NSUInteger count = subcomponents.count;
    for (WXComponent *component in subcomponents) {
        if (!component->_isNeedJoinLayoutSystem) {
            count--;
        }
    }
    return (int)(count);
}

- (void)_frameDidCalculated:(BOOL)isChanged
{
    WXAssertComponentThread();
    
    if ([self isViewLoaded] && isChanged && [self isViewFrameSyncWithCalculated]) {
        
        __weak typeof(self) weakSelf = self;
        [self.weexInstance.componentManager _addUITask:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf->_transform && !CATransform3DEqualToTransform(strongSelf.layer.transform, CATransform3DIdentity)) {
                // From the UIView's frame documentation:
                // https://developer.apple.com/reference/uikit/uiview#//apple_ref/occ/instp/UIView/frame
                // Warning : If the transform property is not the identity transform, the value of this property is undefined and therefore should be ignored.
                // So layer's transform must be reset to CATransform3DIdentity before setFrame, otherwise frame will be incorrect
                strongSelf.layer.transform = CATransform3DIdentity;
            }
            
            if (!CGRectEqualToRect(strongSelf.view.frame,strongSelf.calculatedFrame)) {
                strongSelf.view.frame = strongSelf.calculatedFrame;
                strongSelf->_absolutePosition = CGPointMake(NAN, NAN);
                [strongSelf configBoxShadow:_boxShadow];
            } else {
                if (![strongSelf equalBoxShadow:_boxShadow withBoxShadow:_lastBoxShadow]) {
                    [strongSelf configBoxShadow:_boxShadow];
                }
            }
            
            [self _resetNativeBorderRadius];
            
            if (strongSelf->_transform) {
                [strongSelf->_transform applyTransformForView:strongSelf.view];
            }
            
            if (strongSelf->_backgroundImage) {
                [strongSelf setGradientLayer];
            }
            [strongSelf setNeedsDisplay];
        }];
    }
}

- (void)_calculateFrameWithSuperAbsolutePosition:(CGPoint)superAbsolutePosition
                           gatherDirtyComponents:(NSMutableSet<WXComponent *> *)dirtyComponents
{
    WXAssertComponentThread();
    if (!YGNodeGetHasNewLayout(_cssNode)) {
        return;
    }
    YGNodeSetHasNewLayout(_cssNode, false);
    
    if (YGNodeStyleGetDisplay(_cssNode) == YGDisplayNone) {
        return;
    }
    _isLayoutDirty = NO;
    
    CGRect newFrame = CGRectMake(WXRoundPixelValue(YGNodeLayoutGetLeft(_cssNode)),
                                 WXRoundPixelValue(YGNodeLayoutGetTop(_cssNode)),
                                 WXRoundPixelValue(YGNodeLayoutGetWidth(_cssNode)),
                                 WXRoundPixelValue(YGNodeLayoutGetHeight(_cssNode)));
    
    BOOL isFrameChanged = NO;
    if (!CGRectEqualToRect(newFrame, _calculatedFrame)) {
        isFrameChanged = YES;
        _calculatedFrame = newFrame;
        [dirtyComponents addObject:self];
    }
    
    CGPoint newAbsolutePosition = [self computeNewAbsolutePosition:superAbsolutePosition];
    
//    _cssNode->layout.dimensions[CSS_WIDTH] = CSS_UNDEFINED;
//    _cssNode->layout.dimensions[CSS_HEIGHT] = CSS_UNDEFINED;
//    _cssNode->layout.position[CSS_LEFT] = 0;
//    _cssNode->layout.position[CSS_TOP] = 0;
    
    [self _frameDidCalculated:isFrameChanged];
    
    for (WXComponent *subcomponent in _subcomponents) {
        [subcomponent _calculateFrameWithSuperAbsolutePosition:newAbsolutePosition gatherDirtyComponents:dirtyComponents];
    }
}

- (CGPoint)computeNewAbsolutePosition:(CGPoint)superAbsolutePosition
{
    // Not need absolutePosition any more
    return superAbsolutePosition;
}

- (void)_layoutDidFinish
{
    WXAssertMainThread();
    
    if (_positionType == WXPositionTypeSticky) {
        [self.ancestorScroller adjustSticky];
    }
    [self layoutDidFinish];
}

#define WX_STYLE_FILL_CSS_NODE(key, cssProp, type)\
do {\
    id value = styles[@#key];\
    if (value) {\
    YGNodeStyleSet##cssProp(_cssNode,[WXConvert type:value]);\
        [self setNeedsLayout];\
    }\
} while(0);

#define WX_STYLE_FILL_CSS_NODE_PIXEL(key, cssProp, edge)\
do {\
    id value = styles[@#key];\
    if (value) {\
        CGFloat pixel = [self WXPixelType:value];\
        if (isnan(pixel)) {\
            WXLogError(@"Invalid NaN value for style:%@, ref:%@", @#key, self.ref);\
        } else {\
            YGNodeStyleSet##cssProp(_cssNode,edge, pixel)\
            [self setNeedsLayout];\
        }\
    }\
} while(0);

#define WX_STYLE_FILL_CSS_NODE_ALL_DIRECTION(key, cssProp)\
do {\
    WX_STYLE_FILL_CSS_NODE_PIXEL(key, cssProp[CSS_TOP])\
    WX_STYLE_FILL_CSS_NODE_PIXEL(key, cssProp[CSS_LEFT])\
    WX_STYLE_FILL_CSS_NODE_PIXEL(key, cssProp[CSS_RIGHT])\
    WX_STYLE_FILL_CSS_NODE_PIXEL(key, cssProp[CSS_BOTTOM])\
} while(0);


- (CGFloat)WXPixelType:(id)value
{
    return [WXConvert WXPixelType:value scaleFactor:self.weexInstance.pixelScaleFactor];
}

- (void)_fillCSSNode:(NSDictionary *)styles;
{
    // flex
    YGNodeStyleSe
    WX_STYLE_FILL_CSS_NODE(flex, Flex, CGFloat)
    WX_STYLE_FILL_CSS_NODE(flexDirection, FlexDirection, YGFlexDirection)
    WX_STYLE_FILL_CSS_NODE(alignItems, AlignItems, YGAlign)
    WX_STYLE_FILL_CSS_NODE(alignSelf, AlignSelf, YGAlign)
    WX_STYLE_FILL_CSS_NODE(flexWrap, FlexWrap, YGWrap)
    WX_STYLE_FILL_CSS_NODE(justifyContent, JustifyContent, YGJustify)
    
    // position
    WX_STYLE_FILL_CSS_NODE(position, PositionType, YGPositionType)
    WX_STYLE_FILL_CSS_NODE_PIXEL(top, position, YGEdgeTop)
    WX_STYLE_FILL_CSS_NODE_PIXEL(left, position, YGEdgeLeft)
    WX_STYLE_FILL_CSS_NODE_PIXEL(right, position, YGEdgeRight)
    WX_STYLE_FILL_CSS_NODE_PIXEL(bottom, position, YGEdgeBottom)
    
    // dimension
//    WX_STYLE_FILL_CSS_NODE_PIXEL(width, width)
    WX_STYLE_FILL_CSS_NODE_PIXEL(height, dimensions[CSS_HEIGHT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(minWidth, minDimensions[CSS_WIDTH])
    WX_STYLE_FILL_CSS_NODE_PIXEL(minHeight, minDimensions[CSS_HEIGHT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(maxWidth, maxDimensions[CSS_WIDTH])
    WX_STYLE_FILL_CSS_NODE_PIXEL(maxHeight, maxDimensions[CSS_HEIGHT])
    
    // margin
    WX_STYLE_FILL_CSS_NODE_ALL_DIRECTION(margin, margin)
    WX_STYLE_FILL_CSS_NODE_PIXEL(marginTop, margin[CSS_TOP])
    WX_STYLE_FILL_CSS_NODE_PIXEL(marginLeft, margin[CSS_LEFT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(marginRight, margin[CSS_RIGHT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(marginBottom, margin[CSS_BOTTOM])
    
    // border
    WX_STYLE_FILL_CSS_NODE_ALL_DIRECTION(borderWidth, border)
    WX_STYLE_FILL_CSS_NODE_PIXEL(borderTopWidth, border[CSS_TOP])
    WX_STYLE_FILL_CSS_NODE_PIXEL(borderLeftWidth, border[CSS_LEFT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(borderRightWidth, border[CSS_RIGHT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(borderBottomWidth, border[CSS_BOTTOM])
    
    // padding
    WX_STYLE_FILL_CSS_NODE_ALL_DIRECTION(padding, padding)
    WX_STYLE_FILL_CSS_NODE_PIXEL(paddingTop, padding[CSS_TOP])
    WX_STYLE_FILL_CSS_NODE_PIXEL(paddingLeft, padding[CSS_LEFT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(paddingRight, padding[CSS_RIGHT])
    WX_STYLE_FILL_CSS_NODE_PIXEL(paddingBottom, padding[CSS_BOTTOM])
}

#define WX_STYLE_RESET_CSS_NODE(key, cssProp, defaultValue)\
do {\
    if (styles && [styles containsObject:@#key]) {\
        _cssNode->style.cssProp = defaultValue;\
        [self setNeedsLayout];\
    }\
} while(0);

#define WX_STYLE_RESET_CSS_NODE_ALL_DIRECTION(key, cssProp, defaultValue)\
do {\
    WX_STYLE_RESET_CSS_NODE(key, cssProp[CSS_TOP], defaultValue)\
    WX_STYLE_RESET_CSS_NODE(key, cssProp[CSS_LEFT], defaultValue)\
    WX_STYLE_RESET_CSS_NODE(key, cssProp[CSS_RIGHT], defaultValue)\
    WX_STYLE_RESET_CSS_NODE(key, cssProp[CSS_BOTTOM], defaultValue)\
} while(0);

- (void)_resetCSSNode:(NSArray *)styles;
{
    // flex
    WX_STYLE_RESET_CSS_NODE(flex, flex, 0.0)
    WX_STYLE_RESET_CSS_NODE(flexDirection, flex_direction, CSS_FLEX_DIRECTION_COLUMN)
    WX_STYLE_RESET_CSS_NODE(alignItems, align_items, CSS_ALIGN_STRETCH)
    WX_STYLE_RESET_CSS_NODE(alignSelf, align_self, CSS_ALIGN_AUTO)
    WX_STYLE_RESET_CSS_NODE(flexWrap, flex_wrap, CSS_NOWRAP)
    WX_STYLE_RESET_CSS_NODE(justifyContent, justify_content, CSS_JUSTIFY_FLEX_START)

    // position
    WX_STYLE_RESET_CSS_NODE(position, position_type, CSS_POSITION_RELATIVE)
    WX_STYLE_RESET_CSS_NODE(top, position[CSS_TOP], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(left, position[CSS_LEFT], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(right, position[CSS_RIGHT], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(bottom, position[CSS_BOTTOM], CSS_UNDEFINED)
    
    // dimension
    WX_STYLE_RESET_CSS_NODE(width, dimensions[CSS_WIDTH], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(height, dimensions[CSS_HEIGHT], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(minWidth, minDimensions[CSS_WIDTH], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(minHeight, minDimensions[CSS_HEIGHT], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(maxWidth, maxDimensions[CSS_WIDTH], CSS_UNDEFINED)
    WX_STYLE_RESET_CSS_NODE(maxHeight, maxDimensions[CSS_HEIGHT], CSS_UNDEFINED)
    
    // margin
    WX_STYLE_RESET_CSS_NODE_ALL_DIRECTION(margin, margin, 0.0)
    WX_STYLE_RESET_CSS_NODE(marginTop, margin[CSS_TOP], 0.0)
    WX_STYLE_RESET_CSS_NODE(marginLeft, margin[CSS_LEFT], 0.0)
    WX_STYLE_RESET_CSS_NODE(marginRight, margin[CSS_RIGHT], 0.0)
    WX_STYLE_RESET_CSS_NODE(marginBottom, margin[CSS_BOTTOM], 0.0)
    
    // border
    WX_STYLE_RESET_CSS_NODE_ALL_DIRECTION(borderWidth, border, 0.0)
    WX_STYLE_RESET_CSS_NODE(borderTopWidth, border[CSS_TOP], 0.0)
    WX_STYLE_RESET_CSS_NODE(borderLeftWidth, border[CSS_LEFT], 0.0)
    WX_STYLE_RESET_CSS_NODE(borderRightWidth, border[CSS_RIGHT], 0.0)
    WX_STYLE_RESET_CSS_NODE(borderBottomWidth, border[CSS_BOTTOM], 0.0)
    
    // padding
    WX_STYLE_RESET_CSS_NODE_ALL_DIRECTION(padding, padding, 0.0)
    WX_STYLE_RESET_CSS_NODE(paddingTop, padding[CSS_TOP], 0.0)
    WX_STYLE_RESET_CSS_NODE(paddingLeft, padding[CSS_LEFT], 0.0)
    WX_STYLE_RESET_CSS_NODE(paddingRight, padding[CSS_RIGHT], 0.0)
    WX_STYLE_RESET_CSS_NODE(paddingBottom, padding[CSS_BOTTOM], 0.0)
}

#pragma mark CSS Node Override

static void cssNodePrint(YGNodeRef node)
{
    WXComponent *component = (__bridge WXComponent *)(YGNodeGetContext(node));
    // TODO:
    printf("%s:%s ", component.ref.UTF8String, component->_type.UTF8String);
}

static css_node_t * cssNodeGetChild(void *context, int i)
{
    WXComponent *component = (__bridge WXComponent *)context;
    NSArray *subcomponents = component->_subcomponents;
    for (int j = 0; j <= i && j < subcomponents.count; j++) {
        WXComponent *child = subcomponents[j];
        if (!child->_isNeedJoinLayoutSystem) {
            i++;
        }
    }
    
    if(i >= 0 && i < subcomponents.count){
        WXComponent *child = subcomponents[i];
        return child->_cssNode;
    }
    
    
    WXAssert(NO, @"Can not find component:%@'s css node child at index: %ld, totalCount:%ld", component, i, subcomponents.count);
    return NULL;
}

static bool cssNodeIsDirty(void *context)
{
    WXAssertComponentThread();
    
    WXComponent *component = (__bridge WXComponent *)context;
    BOOL needsLayout = [component needsLayout];
    
    return needsLayout;
}

//typedef YGSize (*YGMeasureFunc)(YGNodeRef node,
//float width,
//YGMeasureMode widthMode,
//float height,
//YGMeasureMode heightMode);
static YGSize cssNodeMeasure(YGNodeRef node, float width, YGMeasureMode widthMode, float height, YGMeasureMode heightMode)
{
    WXComponent *component = (__bridge WXComponent *)(YGNodeGetContext(node));
    CGSize (^measureBlock)(CGSize) = [component measureBlock];
    
    if (!measureBlock) {
        return (YGSize){NAN, NAN};
    }
    
    CGSize constrainedSize = CGSizeMake(width, height);
    CGSize resultSize = measureBlock(constrainedSize);
    
    return (YGSize){resultSize.width, resultSize.height};
}

@end
