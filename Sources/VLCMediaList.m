/*****************************************************************************
 * VLCMediaList.m: VLCKit.framework VLCMediaList implementation
 *****************************************************************************
 * Copyright (C) 2007 Pierre d'Herbemont
 * Copyright (C) 2007 VLC authors and VideoLAN
 * Copyright (C) 2009, 2013 Felix Paul Kühne
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
 *          Felix Paul Kühne <fkuehne # videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCMediaList.h"
#import "VLCLibrary.h"
#import "VLCEventManager.h"
#import "VLCLibVLCBridging.h"
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc/vlc.h>
#include <vlc/libvlc.h>

/* Notification Messages */
NSString *const VLCMediaListItemAdded        = @"VLCMediaListItemAdded";
NSString *const VLCMediaListItemDeleted      = @"VLCMediaListItemDeleted";

// TODO: Documentation
@interface VLCMediaList (Private)
/* Initializers */
- (void)initInternalMediaList;

/* Libvlc event bridges */
- (void)mediaListItemAdded:(NSArray *)args;
- (void)mediaListItemRemoved:(NSNumber *)index;
@end

/* libvlc event callback */
static void HandleMediaListItemAdded(const libvlc_event_t * event, void * user_data)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    id self = user_data;
    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(mediaListItemAdded:)
                                       withArgumentAsObject:@[@{@"media": [VLCMedia mediaWithLibVLCMediaDescriptor:event->u.media_list_item_added.item],
                                                          @"index": @(event->u.media_list_item_added.index)}]];
    [pool release];
}

static void HandleMediaListItemDeleted( const libvlc_event_t * event, void * user_data)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    id self = user_data;
    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(mediaListItemRemoved:)
                                       withArgumentAsObject:@(event->u.media_list_item_deleted.index)];
    [pool release];
}

@implementation VLCMediaList
- (id)init
{
    if (self = [super init]) {
        // Create a new libvlc media list instance
        p_mlist = libvlc_media_list_new([VLCLibrary sharedLibrary].instance);

        // Initialize internals to defaults
        cachedMedia = [[NSMutableArray alloc] init];
        [self initInternalMediaList];
    }

    return self;
}

- (id)initWithArray:(NSArray *)array
{
    if (self = [self init]) {
        /* do something useful with the provided array */
        NSUInteger count = [array count];
        for (NSUInteger x = 0; x < count; x++)
            [self addMedia:array[x]];
    }

    return self;
}

- (void)dealloc
{
    libvlc_event_manager_t *em = libvlc_media_list_event_manager(p_mlist);
    libvlc_event_detach(em, libvlc_MediaListItemDeleted, HandleMediaListItemDeleted, self);
    libvlc_event_detach(em, libvlc_MediaListItemAdded,   HandleMediaListItemAdded,   self);
    [[VLCEventManager sharedManager] cancelCallToObject:self];

    // Release allocated memory
    delegate = nil;

    libvlc_media_list_release( p_mlist );
    [cachedMedia release];
    [super dealloc];
}

- (NSString *)description
{
    NSMutableString * content = [NSMutableString string];
    for (NSInteger i = 0; i < [self count]; i++) {
        [content appendFormat:@"%@\n", [self mediaAtIndex: i]];
    }
    return [NSString stringWithFormat:@"<%@ %p> {\n%@}", [self class], self, content];
}

- (void)lock
{
    libvlc_media_list_lock( p_mlist );
}

- (void)unlock
{
    libvlc_media_list_unlock( p_mlist );
}

- (NSInteger)addMedia:(VLCMedia *)media
{
    NSInteger index = [self count];
    [self insertMedia:media atIndex:index];
    return index;
}

- (void)insertMedia:(VLCMedia *)media atIndex: (NSInteger)index
{
    [media retain];

    // Add it to the libvlc's medialist
    libvlc_media_list_insert_media(p_mlist, [media libVLCMediaDescriptor], (int)index);
}

- (void)removeMediaAtIndex:(NSInteger)index
{
    if (index < [cachedMedia count]) {
        [cachedMedia removeObjectAtIndex:index];

        // Remove it from the libvlc's medialist
        libvlc_media_list_remove_index(p_mlist, (int)index);
    }
}

- (VLCMedia *)mediaAtIndex:(NSInteger)index
{
    if (index < [cachedMedia count])
        return cachedMedia[index];
    return NULL;
}

- (NSInteger)indexOfMedia:(VLCMedia *)media
{
    NSInteger result = libvlc_media_list_index_of_item(p_mlist, [media libVLCMediaDescriptor]);
    return result;
}

/* KVC Compliance: For the @"media" key */
- (NSInteger)countOfMedia
{
    return [self count];
}

- (id)objectInMediaAtIndex:(NSUInteger)i
{
    return [self mediaAtIndex:i];
}

- (NSInteger)count
{
    return [cachedMedia count];
}

- (void)insertObject:(id)object inMediaAtIndex:(NSUInteger)i
{
    [self insertMedia:object atIndex:i];
}

- (void)removeObjectFromMediaAtIndex:(NSUInteger)i
{
    [self removeMediaAtIndex:i];
}

@synthesize delegate;

- (BOOL)isReadOnly
{
    return libvlc_media_list_is_readonly( p_mlist );
}

@end

@implementation VLCMediaList (LibVLCBridging)
+ (id)mediaListWithLibVLCMediaList:(void *)p_new_mlist;
{
    return [[[VLCMediaList alloc] initWithLibVLCMediaList:p_new_mlist] autorelease];
}

- (id)initWithLibVLCMediaList:(void *)p_new_mlist;
{
    if (self = [super init]) {
        p_mlist = p_new_mlist;
        libvlc_media_list_retain( p_mlist );
        libvlc_media_list_lock( p_mlist );
        cachedMedia = [[NSMutableArray alloc] initWithCapacity:libvlc_media_list_count(p_mlist)];

        NSUInteger count = libvlc_media_list_count(p_mlist);
        for (int i = 0; i < count; i++) {
            libvlc_media_t * p_md = libvlc_media_list_item_at_index(p_mlist, i);
            [cachedMedia addObject:[VLCMedia mediaWithLibVLCMediaDescriptor:p_md]];
            libvlc_media_release(p_md);
        }
        [self initInternalMediaList];
        libvlc_media_list_unlock(p_mlist);
    }
    return self;
}

- (void *)libVLCMediaList
{
    return p_mlist;
}
@end

@implementation VLCMediaList (Private)
- (void)initInternalMediaList
{
    // Add event callbacks
    libvlc_event_manager_t * p_em = libvlc_media_list_event_manager(p_mlist);
    libvlc_event_attach( p_em, libvlc_MediaListItemAdded,   HandleMediaListItemAdded,   self);
    libvlc_event_attach( p_em, libvlc_MediaListItemDeleted, HandleMediaListItemDeleted, self);
}

- (void)mediaListItemAdded:(NSArray *)arrayOfArgs
{
    /* We hope to receive index in a nide range, that could change one day */
    NSInteger start = [arrayOfArgs[0][@"index"] intValue];
    NSInteger end = [arrayOfArgs[[arrayOfArgs count]-1][@"index"] intValue];
    NSRange range = NSMakeRange(start, end-start);

    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range] forKey:@"media"];
    for (NSDictionary * args in arrayOfArgs) {
        NSInteger index = [args[@"index"] intValue];
        VLCMedia * media = args[@"media"];
        /* Sanity check */
        if (index && index > [cachedMedia count])
            index = [cachedMedia count];
        [cachedMedia insertObject:media atIndex:index];
    }
    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range] forKey:@"media"];

    // Post the notification
//    [[NSNotificationCenter defaultCenter] postNotificationName:VLCMediaListItemAdded
//                                                        object:self
//                                                      userInfo:args];

    // Let the delegate know that the item was added
  //  if (delegate && [delegate respondsToSelector:@selector(mediaList:mediaAdded:atIndex:)])
    //    [delegate mediaList:self mediaAdded:media atIndex:index];
}

- (void)mediaListItemRemoved:(NSNumber *)index
{
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:[index intValue]] forKey:@"media"];
    [cachedMedia removeObjectAtIndex:[index intValue]];
    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:[index intValue]] forKey:@"media"];

    // Post the notification
    [[NSNotificationCenter defaultCenter] postNotificationName:VLCMediaListItemDeleted
                                                        object:self
                                                      userInfo:@{@"index": index}];

    // Let the delegate know that the item is being removed
    if (delegate && [delegate respondsToSelector:@selector(mediaList:mediaRemovedAtIndex:)])
        [delegate mediaList:self mediaRemovedAtIndex:[index intValue]];
}
@end
