package migration

import (
	"context"

	appsv1 "k8s.io/api/apps/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/util/workqueue"

	"github.com/kcp-dev/logicalcluster"

	"github.com/kuadrant/kcp-glbc/pkg/reconciler"
)

const controllerNamePrefix = "kcp-glbc-"

// NewController returns a new Controller which reconciles resources.
func NewController(config *ControllerConfig) (*Controller, error) {
	controllerName := controllerNamePrefix + config.controllerNameSuffix
	queue := workqueue.NewNamedRateLimitingQueue(workqueue.DefaultControllerRateLimiter(), controllerName)
	c := &Controller{
		Controller:          reconciler.NewController(controllerName, queue),
		coreClient:          config.ResourceClient,
		sharedIndexInformer: config.SharedIndexInformer,
	}
	c.Process = c.process

	c.sharedIndexInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc:    func(obj interface{}) { c.Enqueue(obj) },
		UpdateFunc: func(_, obj interface{}) { c.Enqueue(obj) },
		DeleteFunc: func(obj interface{}) { c.Enqueue(obj) },
	})

	c.indexer = c.sharedIndexInformer.GetIndexer()

	return c, nil
}

type ControllerConfig struct {
	ResourceClient      kubernetes.ClusterInterface
	SharedIndexInformer cache.SharedIndexInformer
}

type Controller struct {
	*reconciler.Controller
	SharedIndexInformer cache.SharedIndexInformer
	coreClient          kubernetes.ClusterInterface
	indexer             cache.Indexer
}

func (c *Controller) process(ctx context.Context, key string) error {
	object, exists, err := c.indexer.GetByKey(key)
	if err != nil {
		return err
	}

	if !exists {
		c.Logger.Info("Resource was deleted", "key", key)
		return nil
	}

	current := object.(*appsv1.Deployment)
	target := current.DeepCopy()

	if err = c.reconcile(ctx, target); err != nil {
		return err
	}

	// If the object being reconciled changed as a result, update it.
	if !equality.Semantic.DeepEqual(target, current) {
		_, err := c.coreClient.Cluster(logicalcluster.From(target)).AppsV1().Deployments(target.Namespace).Update(ctx, target, metav1.UpdateOptions{})
		return err
	}

	return nil
}
