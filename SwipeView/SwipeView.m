//
//  SwipeView.m
//
//  Version 1.2.9
//
//  Created by Nick Lockwood on 03/09/2010.
//  Copyright 2010 Charcoal Design
//
//  Distributed under the permissive zlib License
//  Get the latest version of SwipeView from here:
//
//  https://github.com/nicklockwood/SwipeView
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

//
//  ARC Helper
//
//  Version 2.1
//
//  Created by Nick Lockwood on 05/01/2012.
//  Copyright 2012 Charcoal Design
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://gist.github.com/1563325
//

#ifndef ah_retain
#if __has_feature(objc_arc)
#define ah_retain self
#define ah_dealloc self
#define release self
#define autorelease self
#else
#define ah_retain retain
#define ah_dealloc dealloc
#define __bridge
#endif
#endif

//  ARC Helper ends


#import "SwipeView.h"


@interface SwipeView () <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSMutableDictionary *itemViews;
@property (nonatomic, strong) NSMutableSet *itemViewPool;
@property (nonatomic, assign) NSInteger previousItemIndex;
@property (nonatomic, assign) CGPoint previousContentOffset;
@property (nonatomic, assign) CGFloat scrollOffset;
@property (nonatomic, assign) CGSize itemSize;
@property (nonatomic, assign) BOOL suppressScrollEvent;
@property (nonatomic, assign) NSTimeInterval scrollDuration;
@property (nonatomic, assign, getter = isScrolling) BOOL scrolling;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) CGFloat startOffset;
@property (nonatomic, assign) CGFloat endOffset;
@property (nonatomic, assign) CGFloat lastUpdateOffset;
@property (nonatomic, unsafe_unretained) NSTimer *timer;
@property (nonatomic) NSInteger numberOfItems;
@end

@implementation SwipeView

//@synthesize currentItemView = _currentItemView;

- (void)dealloc {
    [_timer invalidate];
    [_scrollView release];
    [_itemViews release];
    [_itemViewPool release];
//	[_currentItemView release];
    [super ah_dealloc];
}

#pragma mark - Initialisation

- (void) setUp {
    _scrollEnabled = YES;
    _pagingEnabled = YES;
    _delaysContentTouches = YES;
    _itemsPerPage = 1;
    _defersItemViewLoading = NO;
    
    _scrollView = [[UIScrollView alloc] init];
	_scrollView.delegate = self;
	_scrollView.delaysContentTouches = _delaysContentTouches;
    _scrollView.bounces = YES;
	_scrollView.alwaysBounceHorizontal = YES;
    _scrollView.alwaysBounceVertical = NO;
	_scrollView.pagingEnabled = _pagingEnabled;
	_scrollView.scrollEnabled = _scrollEnabled;
    _scrollView.decelerationRate = _decelerationRate;
	_scrollView.showsHorizontalScrollIndicator = NO;
	_scrollView.showsVerticalScrollIndicator = NO;
	_scrollView.scrollsToTop = NO;
	_scrollView.clipsToBounds = NO;
    
    _decelerationRate = _scrollView.decelerationRate;
    _itemViews = [[NSMutableDictionary alloc] init];
    _previousItemIndex = 0;
    _previousContentOffset = _scrollView.contentOffset;
    _scrollOffset = 0.0f;
    _currentItemIndex = 0;
    _numberOfItems = 0;
    
    self.clipsToBounds = YES;
    
    //place scrollview at bottom of hierarchy
    [self insertSubview:_scrollView atIndex:0];
}

#pragma mark - Init Methods

- (id) initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        [self setUp];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setUp];
    }
    return self;
}

#pragma mark - Delegate and Datasource

- (void)setDataSource:(id<SwipeViewDataSource>)dataSource {
    if (_dataSource != dataSource) {
        _dataSource = dataSource;
        if (_dataSource) {
            //[self reloadData];
        }
    }
}

- (void)setDelegate:(id<SwipeViewDelegate>)delegate {
    if (_delegate != delegate) {
        _delegate = delegate;
		//[self setNeedsLayout];
    }
}


- (void)setItemsPerPage:(NSInteger)itemsPerPage {
    if (_itemsPerPage != itemsPerPage) {
        _itemsPerPage = itemsPerPage;
        [self setNeedsLayout];
    }
}

- (void)setScrollEnabled:(BOOL)scrollEnabled {
    if (_scrollEnabled != scrollEnabled) {
        _scrollEnabled = scrollEnabled;
        _scrollView.scrollEnabled = _scrollEnabled;
    }
}

- (void)setPagingEnabled:(BOOL)pagingEnabled {
    if (_pagingEnabled != pagingEnabled) {
        _pagingEnabled = pagingEnabled;
        _scrollView.pagingEnabled = pagingEnabled;
        [self setNeedsLayout];
    }
}

- (void)setDelaysContentTouches:(BOOL)delaysContentTouches {
    _delaysContentTouches = delaysContentTouches;
    _scrollView.delaysContentTouches = delaysContentTouches;
}

- (void)setDecelerationRate:(float)decelerationRate {
    if (_decelerationRate != decelerationRate) {
        _decelerationRate = decelerationRate;
        _scrollView.decelerationRate = _decelerationRate;
    }
}

- (void)setAlignment:(SwipeViewAlignment)alignment {
    if (_alignment != alignment) {
        _alignment = alignment;
        [self setNeedsLayout];
    }
}

- (BOOL)isDragging {
    return _scrollView.dragging;
}

- (BOOL)isDecelerating {
    return _scrollView.decelerating;
}


#pragma mark -  View management

- (NSArray *)indexesForVisibleItems {
    return [[_itemViews allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray *)visibleItemViews {
    NSArray *indexes = [self indexesForVisibleItems];
    return [_itemViews objectsForKeys:indexes notFoundMarker:[NSNull null]];
}

- (UIView *)itemViewAtIndex:(NSInteger)index {
    return _itemViews[@(index)];
}

- (UIView *)currentItemView {
    return [self itemViewAtIndex:_currentItemIndex];
}

- (NSInteger)indexOfItemView:(UIView *)view {
    NSInteger index = [[_itemViews allValues] indexOfObject:view];
    if (index != NSNotFound) {
        return [[_itemViews allKeys][index] integerValue];
    }
    return NSNotFound;
}

- (NSInteger)indexOfItemViewOrSubview:(UIView *)view {
    NSInteger index = [self indexOfItemView:view];
    if (index == NSNotFound && view != nil && view != _scrollView) {
        return [self indexOfItemViewOrSubview:view.superview];
    }
    return index;
}

- (void)setItemView:(UIView *)view forIndex:(NSInteger)index {
    ((NSMutableDictionary *)_itemViews)[@(index)] = view;
}


#pragma mark -  View layout

- (void)updateScrollOffset {
	CGFloat scrollWidth = _scrollView.contentSize.width / 3.0f;
	//CGFloat contentOffsetX = _scrollView.contentOffset.x;
	if (_scrollView.contentOffset.x < scrollWidth)
	{
		_previousContentOffset.x += scrollWidth;
		[self setContentOffsetWithoutEvent:CGPointMake(_scrollView.contentOffset.x + scrollWidth, 0.0f)];
		//[self setContentOffsetWithoutEvent:CGPointMake(scrollWidth, 0.0f)];
	}
	else if (_scrollView.contentOffset.x >= scrollWidth * 2.0f)
	{
		_previousContentOffset.x -= scrollWidth;
		[self setContentOffsetWithoutEvent:CGPointMake(_scrollView.contentOffset.x - scrollWidth, 0.0f)];
	}
	_scrollOffset = [self clampedOffset:_scrollOffset];
}

- (void)updateScrollViewDimensions {
    CGRect frame = self.bounds;
    CGSize contentSize = frame.size;
	
	
	switch (self.alignment) {
		case SwipeViewAlignmentCenter: {
			frame = CGRectMake((self.frame.size.width - _itemSize.width * _itemsPerPage)/2.0f,
							   0.0f, _itemSize.width * _itemsPerPage, self.frame.size.height);
			contentSize.width = _itemSize.width * _numberOfItems;
			break;
		}
		case SwipeViewAlignmentEdge: {
			frame = CGRectMake(0.0f, 0.0f, _itemSize.width * _itemsPerPage, self.frame.size.height);
			contentSize.width = _itemSize.width * _numberOfItems - (self.frame.size.width - frame.size.width);
			break;
		}
		default:
			break;
	}
	
	
	contentSize.width = _itemSize.width * _numberOfItems * 3.0f;
	
	if (!CGRectEqualToRect(_scrollView.frame, frame)) {
		_scrollView.frame = frame;
	}
	
	if (!CGSizeEqualToSize(_scrollView.contentSize, contentSize)) {
		_scrollView.contentSize = contentSize;
	}
	
}



- (CGFloat)offsetForItemAtIndex:(NSInteger)index {
    //calculate relative position
    CGFloat offset = index - _scrollOffset;
	
	
	if (_alignment == SwipeViewAlignmentCenter) {
		if (offset > _numberOfItems/2) {
			offset -= _numberOfItems;
		} else if (offset < -_numberOfItems/2)
		{
			offset += _numberOfItems;
		}
	} else {
		CGFloat width =  self.bounds.size.width;
		CGFloat x =  _scrollView.frame.origin.x;
		CGFloat itemWidth = _itemSize.width;
		if (offset * itemWidth + x > width) {
			offset -= _numberOfItems;
		} else if (offset * itemWidth + x < -itemWidth) {
			offset += _numberOfItems;
		}
	}
	
    return offset;
}


- (void)setFrameForView:(UIView *)view atIndex:(NSInteger)index {
	view.center = CGPointMake(([self offsetForItemAtIndex:index] + 0.5f) * _itemSize.width + _scrollView.contentOffset.x, _scrollView.frame.size.height/2.0f);
}

- (void)layOutItemViews {
    for (UIView *view in self.visibleItemViews) {
        [self setFrameForView:view atIndex:[self indexOfItemView:view]];
    }
}



#pragma mark -  View queing

- (void)queueItemView:(UIView *)view {
    if (view) {
        [_itemViewPool addObject:view];
    }
}

- (UIView *)dequeueItemView {
    UIView *view = [[_itemViewPool anyObject] ah_retain];
    if (view) {
        [_itemViewPool removeObject:view];
    }
    return [view autorelease];
}


#pragma mark - Scrolling

- (void)didScroll {
    //handle wrap
    [self updateScrollOffset];
    
    //update view
    [self layOutItemViews];
    if ([_delegate respondsToSelector:@selector(swipeViewDidScroll:)]) {
        [_delegate swipeViewDidScroll:self];
    }
    
    if (!_defersItemViewLoading || fabs([self minScrollDistanceFromOffset:_lastUpdateOffset toOffset:_scrollOffset]) >= 1.0f) {
        //update item index
        _currentItemIndex = [self clampedIndex:roundf(_scrollOffset)];
        
        //load views
        _lastUpdateOffset = _currentItemIndex;
        [self loadUnloadViews];
        
        //send index update event
        if (_previousItemIndex != _currentItemIndex) {
            _previousItemIndex = _currentItemIndex;
            if ([_delegate respondsToSelector:@selector(swipeViewCurrentItemIndexDidChange:)]) {
                [_delegate swipeViewCurrentItemIndexDidChange:self];
            }
        }
    }
	
//	UIView *nextView = [self.visibleItemViews objectAtIndex:self.currentItemIndex];
//	if (nextView) {
//		self.currentItemView =  nextView;
//	}
	
}

- (CGFloat)easeInOut:(CGFloat)time {
    return (time < 0.5f)? 0.5f * powf(time * 2.0f, 3.0f): 0.5f * powf(time * 2.0f - 2.0f, 3.0f) + 1.0f;
}

- (void) step {
    if (_scrolling) {
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSinceReferenceDate];
        NSTimeInterval time = fminf(1.0f, (currentTime - _startTime) / _scrollDuration);
        CGFloat delta = [self easeInOut:time];
        _scrollOffset = [self clampedOffset:_startOffset + (_endOffset - _startOffset) * delta];
		
		[self setContentOffsetWithoutEvent:CGPointMake(_scrollOffset * _itemSize.width, 0.0f)];
        
        [self didScroll];
        if (time == 1.0f) {
            _scrolling = NO;
            [self didScroll];
            if ([_delegate respondsToSelector:@selector(swipeViewDidEndScrollingAnimation:)]) {
                [_delegate swipeViewDidEndScrollingAnimation:self];
            }
        }
    }  else {
        [self stopAnimation];
    }
}

- (void)startAnimation {
    if (!_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                  target:self
                                                selector:@selector(step)
                                                userInfo:nil
                                                 repeats:YES];
    }
}

- (void)stopAnimation {
    [_timer invalidate];
    _timer = nil;
}

- (NSInteger)clampedIndex:(NSInteger)index {
	if (_numberOfItems == 0) {
		return 0;
	}
	return index - floorf((CGFloat)index / (CGFloat)_numberOfItems) * _numberOfItems;
}

- (CGFloat)clampedOffset:(CGFloat)offset {    
	return _numberOfItems? (offset - floorf(offset / (CGFloat)_numberOfItems) * _numberOfItems): 0.0f;
}

- (void)setContentOffsetWithoutEvent:(CGPoint)contentOffset {
    //[UIView setAnimationsEnabled:NO];
    _suppressScrollEvent = YES;
    [_scrollView setContentOffset:contentOffset animated:NO];
    _suppressScrollEvent = NO;
    //[UIView setAnimationsEnabled:YES];
}

- (NSInteger)currentPage {
    return roundf((float)_currentItemIndex / (float)_itemsPerPage);
}

- (NSInteger)numberOfItems {
    return ((_numberOfItems = [_dataSource numberOfItemsInSwipeView:self]));
}

- (NSInteger)numberOfPages {
    return ceilf((float)self.numberOfItems / (float)_itemsPerPage);
}

- (NSInteger)minScrollDistanceFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
    NSInteger directDistance = toIndex - fromIndex;
    
	NSInteger wrappedDistance = MIN(toIndex, fromIndex) + _numberOfItems - MAX(toIndex, fromIndex);
	if (fromIndex < toIndex) {
		wrappedDistance = -wrappedDistance;
	}
	return (ABS(directDistance) <= ABS(wrappedDistance))? directDistance: wrappedDistance;
    
    return directDistance;
}

- (CGFloat)minScrollDistanceFromOffset:(CGFloat)fromOffset toOffset:(CGFloat)toOffset {
    CGFloat directDistance = toOffset - fromOffset;
	
	CGFloat wrappedDistance = fminf(toOffset, fromOffset) + _numberOfItems - fmaxf(toOffset, fromOffset);
	if (fromOffset < toOffset) {
		wrappedDistance = -wrappedDistance;
	}
	return (fabs(directDistance) <= fabs(wrappedDistance))? directDistance: wrappedDistance;
    
    return directDistance;
}

- (void)setCurrentItemIndex:(NSInteger)currentItemIndex {
    _currentItemIndex = currentItemIndex;
    self.scrollOffset = currentItemIndex;
}

- (void)setCurrentPage:(NSInteger)currentPage {
    if (currentPage * _itemsPerPage != _currentItemIndex) {
        [self scrollToPage:currentPage duration:0.0];
    }
}

- (void)setScrollOffset:(CGFloat)scrollOffset {
    if (_scrollOffset != scrollOffset) {
        _scrollOffset = scrollOffset;
        _lastUpdateOffset = _scrollOffset - 1.0f; //force refresh
        _scrolling = NO; //stop scrolling
        [self updateLayout];
        CGPoint contentOffset = CGPointMake([self clampedOffset:scrollOffset] * _itemSize.width, 0.0f);
        [self setContentOffsetWithoutEvent:contentOffset];
        [self didScroll];
    }
}

- (void)scrollByOffset:(CGFloat)offset duration:(NSTimeInterval)duration {
    if (duration > 0.0)  {
        _scrolling = YES;
        _startTime = [[NSDate date] timeIntervalSinceReferenceDate];
        _startOffset = _scrollOffset;
        _scrollDuration = duration;
        _endOffset = _startOffset + offset;
        [self startAnimation];
    } else {
        self.scrollOffset += offset;
    }
}

- (void)scrollToOffset:(CGFloat)offset duration:(NSTimeInterval)duration {
    _numberOfItems = [_dataSource numberOfItemsInSwipeView:self];
    [self scrollByOffset:[self minScrollDistanceFromOffset:_scrollOffset toOffset:offset] duration:duration];
}

- (void)scrollByNumberOfItems:(NSInteger)itemCount duration:(NSTimeInterval)duration {
    if (duration > 0.0) {
        CGFloat offset = 0.0f;
        if (itemCount > 0) {
            offset = (floorf(_scrollOffset) + itemCount) - _scrollOffset;
        }  else if (itemCount < 0) {
            offset = (ceilf(_scrollOffset) + itemCount) - _scrollOffset;
        } else {
            offset = roundf(_scrollOffset) - _scrollOffset;
        }
        [self scrollByOffset:offset duration:duration];
    }  else {
        self.scrollOffset = [self clampedIndex:_previousItemIndex + itemCount];
    }
}

- (void)scrollToItemAtIndex:(NSInteger)index duration:(NSTimeInterval)duration {
    [self scrollToOffset:index duration:duration];
}

- (void)scrollToPage:(NSInteger)page duration:(NSTimeInterval)duration {
    NSInteger index = page * _itemsPerPage;
	
    [self scrollToItemAtIndex:index duration:duration];
}


#pragma mark - View loading

- (UIView *)loadViewAtIndex:(NSInteger)index {
	
	
	
    UIView *view = nil;
//	if (index == self.currentItemIndex && self.currentItemView) {
//		view = self.currentItemView;
//		
//	} else {
		view = [_dataSource swipeView:self viewForItemAtIndex:index reusingView:[self dequeueItemView]];
//	}
		
    if (view == nil) {
        view = [[[UIView alloc] init] autorelease];
    }
    
    UIView *oldView = [self itemViewAtIndex:index];
    if (oldView) {
        [self queueItemView:oldView];
        [oldView removeFromSuperview];
    }
    
    [self setItemView:view forIndex:index];
    [self setFrameForView:view atIndex:index];
    [_scrollView addSubview:view];
    
    return view;
}

- (void)updateItemSizeAndCount {
    //get number of items
    _numberOfItems = [_dataSource numberOfItemsInSwipeView:self];
    
    //get item size
    if ([_delegate respondsToSelector:@selector(swipeViewItemSize:)]) {
        _itemSize = [_delegate swipeViewItemSize:self];
    } else if (_numberOfItems > 0) {
        UIView *view = [[self visibleItemViews] lastObject] ?: [_dataSource swipeView:self viewForItemAtIndex:0 reusingView:[self dequeueItemView]];
        _itemSize = view.frame.size;
    }
}

- (void) loadUnloadViews {
    //check that item size is known
    CGFloat itemWidth = _itemSize.width;
    if (itemWidth) {
        //calculate offset and bounds
        CGFloat width = self.bounds.size.width;
        CGFloat x = _scrollView.frame.origin.x;
        
        //calculate range
        CGFloat startOffset = [self clampedOffset:_scrollOffset - x / itemWidth];
        NSInteger startIndex = floorf(startOffset);
        NSInteger numberOfVisibleItems =  ceilf(width / itemWidth + (startOffset - startIndex));
        if (_defersItemViewLoading) {
            startIndex = _currentItemIndex - ceilf(x / itemWidth) - 1;
            numberOfVisibleItems = ceilf(width / itemWidth) + 3;
        }
        
        //create indices
        numberOfVisibleItems = MIN(numberOfVisibleItems, _numberOfItems);
        NSMutableSet *visibleIndices = [NSMutableSet setWithCapacity:numberOfVisibleItems];
        for (NSInteger i = 0; i < numberOfVisibleItems; i++) {
            NSInteger index = [self clampedIndex:i + startIndex];
            [visibleIndices addObject:@(index)];
        }
        
        //remove offscreen views
        for (NSNumber *number in [_itemViews allKeys]) {
            if (![visibleIndices containsObject:number]) {
                UIView *view = _itemViews[number];
                [self queueItemView:view];
                [view removeFromSuperview];
                [_itemViews removeObjectForKey:number];
            }
        }
        
        //add onscreen views
        for (NSNumber *number in visibleIndices)  {
            UIView *view = _itemViews[number];
            if (view == nil) {
                [self loadViewAtIndex:[number integerValue]];
            } 
        }
    }
}

- (void)reloadItemAtIndex:(NSInteger)index {
    //if view is visible
    if ([self itemViewAtIndex:index]) {
        //reload view
        [self loadViewAtIndex:index];
    }
}

- (void) prepareForNewStream {
    _previousItemIndex = 0;
    _scrollOffset = 0.0f;
    _currentItemIndex = 0;
    _lastUpdateOffset = -1.0f;
}

- (void) reloadData {
    //reset properties
    [self setContentOffsetWithoutEvent:CGPointZero];
    _scrollView.contentSize = CGSizeZero;
    //_previousItemIndex = 0;
    //_scrollOffset = 0.0f;
    //_currentItemIndex = 0;
    //_lastUpdateOffset = -1.0f;
    _itemSize = CGSizeZero;
    _scrolling = NO;
    
    //remove old views
    for (UIView *view in self.visibleItemViews) {
        [view removeFromSuperview];
    }
    
    //reset view pools
    self.itemViews = [NSMutableDictionary dictionary];
    self.itemViewPool = [NSMutableSet set];
    
    //layout views
    [self setNeedsLayout];
}

//- (void) setCurrentItemView:(UIView *)currentItemView {
//	[currentItemView retain];
//	[_currentItemView release];
//	_currentItemView = currentItemView;
//}

#pragma mark - Rotation

//- (void) rotateScrollView {
//	
//	[self reloadData];
//	
//	return;
//	
//	//[self setContentOffsetWithoutEvent:CGPointZero];
//	
//	//reset properties
//    [self setContentOffsetWithoutEvent:CGPointZero];
//    _scrollView.contentSize = CGSizeZero;
//    //_previousItemIndex = 0;
//    //_scrollOffset = 0.0f;
//    //_currentItemIndex = 0;
//    //_lastUpdateOffset = -1.0f;
//    _itemSize = CGSizeZero;
//    _scrolling = NO;
//    
//    //remove old views
//    //remove old views
//    for (UIView *view in self.visibleItemViews) {
//		if (view != self.currentItemView) {
//			[view removeFromSuperview];
//		}		
//    }
//    
//    //reset view pools
//	UIView *current = self.currentItemView;
//    self.itemViews = [NSMutableDictionary dictionary];
//	[self.itemViews setObject:current forKey:@(self.currentItemIndex)];
//	
//    self.itemViewPool = [NSMutableSet set];
//    
//    //layout views
//    [self updateLayout];
//	
//	
//	[self setFrameForView:current atIndex:[self indexOfItemView:current]];
//	CGRect frame = current.frame;
//	frame.size = _itemSize;
//	current.frame = frame;
//}

- (void) updateLayout {
    [self updateItemSizeAndCount];
    [self updateScrollViewDimensions];
    [self updateScrollOffset];
    //[UIView setAnimationsEnabled:NO];
    [self loadUnloadViews];
    //[UIView setAnimationsEnabled:YES];
    [self layOutItemViews];
}

- (void) layoutSubviews {
    [super layoutSubviews];
    [self updateLayout];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	UIView *view = [super hitTest:point withEvent:event];
	if ([view isEqual:self]) {
        for (UIView *subview in _scrollView.subviews) {
            CGPoint offset = CGPointMake(point.x - _scrollView.frame.origin.x + _scrollView.contentOffset.x - subview.frame.origin.x,
                                         point.y - _scrollView.frame.origin.y + _scrollView.contentOffset.y - subview.frame.origin.y);
            
            if ((view = [subview hitTest:offset withEvent:event])) {
                return view;
            }
        }
		return _scrollView;
	}
	return view;
}

//- (void)didMoveToSuperview {
//    if (self.superview) {
//		[self setNeedsLayout];
//        if (_scrolling) {
//            [self startAnimation];
//        }
//	} else {
//        [self stopAnimation];
//    }
//}

#pragma mark -  Gestures and taps

- (NSInteger)viewOrSuperviewIndex:(UIView *)view {
    if (view == nil || view == _scrollView){
        return NSNotFound;
    }
    NSInteger index = [self indexOfItemView:view];
    if (index == NSNotFound){
        return [self viewOrSuperviewIndex:view.superview];
    }
    return index;
}

- (BOOL)viewOrSuperview:(UIView *)view isKindOfClass:(Class)class{
    if (view == nil || view == _scrollView) {
        return NO;
    }else if ([view isKindOfClass:class]){
        return YES;
    }
    return [self viewOrSuperview:view.superview isKindOfClass:class];
}

//- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
//    if ([gesture isKindOfClass:[UITapGestureRecognizer class]])
//    {
//        //handle tap
//        NSInteger index = [self viewOrSuperviewIndex:touch.view];
//        if (index != NSNotFound)
//        {
//            if ([_delegate respondsToSelector:@selector(swipeView:shouldSelectItemAtIndex:)])
//            {
//                if (![_delegate swipeView:self shouldSelectItemAtIndex:index])
//                {
//                    return NO;
//                }
//            }
//            if ([self viewOrSuperview:touch.view isKindOfClass:[UIControl class]] ||
//                [self viewOrSuperview:touch.view isKindOfClass:[UITableViewCell class]])
//            {
//                return NO;
//            }
//        }
//    }
//    return YES;
//}


#pragma mark -  UIScrollViewDelegate methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!_suppressScrollEvent){
        //stop scrolling animation
        _scrolling = NO;
        
        //update scrollOffset
        CGFloat delta =  (_scrollView.contentOffset.x - _previousContentOffset.x);
        _previousContentOffset = _scrollView.contentOffset;
        _scrollOffset += delta / _itemSize.width;
        
        //update view and call delegate
        [self didScroll];
    }else {
        _previousContentOffset = _scrollView.contentOffset;
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView{
    if ([_delegate respondsToSelector:@selector(swipeViewWillBeginDragging:)]){
        [_delegate swipeViewWillBeginDragging:self];
    }
    
    //force refresh
    _lastUpdateOffset = self.scrollOffset - 1.0f;
    [self didScroll];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
    if (!decelerate){
        //force refresh
        _lastUpdateOffset = self.scrollOffset - 1.0f;
        [self didScroll];
    }
    if ([_delegate respondsToSelector:@selector(swipeViewDidEndDragging:willDecelerate:)]){
        [_delegate swipeViewDidEndDragging:self willDecelerate:decelerate];
    }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView{
    if ([_delegate respondsToSelector:@selector(swipeViewWillBeginDecelerating:)]) {
        [_delegate swipeViewWillBeginDecelerating:self];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView{
    //prevent rounding errors from accumulating
    CGFloat integerOffset = roundf(_scrollOffset);
    if (fabs(_scrollOffset - integerOffset) < 0.01f){
        _scrollOffset = integerOffset;
    }
    
    //force refresh
    _lastUpdateOffset = self.scrollOffset - 1.0f;
    [self didScroll];
    
    if ([_delegate respondsToSelector:@selector(swipeViewDidEndDecelerating:)]){
        [_delegate swipeViewDidEndDecelerating:self];
    }
}

@end